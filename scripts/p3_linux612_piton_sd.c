// SPDX-License-Identifier: GPL-2.0-only
/*
 * OpenPiton+Ariane FPGA SD-card aperture block driver for Linux 6.12.
 *
 * The hardware exposes sector N at PITON_SD_BASE_ADDR + (N << 9).  Reads and
 * writes to that MMIO aperture are converted by the OpenPiton SD transaction
 * manager into synchronous 512-byte SD-card operations.
 *
 * The original SDK driver targeted Linux 4.20 and used blk_alloc_queue(),
 * blk_queue_make_request(), and alloc_disk().  This version uses the Linux
 * 6.12 direct-submit block API and serializes MMIO access so one SD transaction
 * is active even when several harts submit I/O concurrently.
 */

#include <linux/bio.h>
#include <linux/blkdev.h>
#include <linux/fs.h>
#include <linux/highmem.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/spinlock.h>
#include <linux/unaligned.h>

#define PITON_SD_NAME              "piton_sd"
#define PITON_SD_BASE_ADDR         0xf000000000ULL
#define PITON_SD_SECTOR_SHIFT      9
#define PITON_SD_SECTOR_SIZE       (1U << PITON_SD_SECTOR_SHIFT)
#define PITON_SD_MINORS            128
#define PITON_SD_GPT_SIGNATURE     0x5452415020494645ULL
#define PITON_SD_GPT_BACKUP_LBA    32
#define PITON_SD_MIN_SECTORS       35ULL
#define PITON_SD_MAX_SECTORS       (1ULL << 28)
#define PITON_SD_MAX_BIO_SECTORS   8U

static int piton_sd_major;
static struct gendisk *piton_sd_disk;
static void __iomem *piton_sd_base;
static u64 piton_sd_sectors;
static DEFINE_SPINLOCK(piton_sd_lock);

static void piton_sd_transfer(bool write, void *buffer, sector_t sector,
			      size_t length)
{
	u8 *bytes = buffer;
	u8 __iomem *mmio = piton_sd_base + ((u64)sector << PITON_SD_SECTOR_SHIFT);
	size_t offset;

	for (offset = 0; offset < length; offset += sizeof(u64)) {
		u64 value;

		if (write) {
			memcpy(&value, bytes + offset, sizeof(value));
			iowrite64(value, mmio + offset);
		} else {
			value = ioread64(mmio + offset);
			memcpy(bytes + offset, &value, sizeof(value));
		}
	}
}

static void piton_sd_submit_bio(struct bio *bio)
{
	struct bio_vec bvec;
	struct bvec_iter iter;
	sector_t sector = bio->bi_iter.bi_sector;
	unsigned long flags;
	bool write;

	if (bio_op(bio) == REQ_OP_FLUSH) {
		bio_endio(bio);
		return;
	}
	if (bio_op(bio) != REQ_OP_READ && bio_op(bio) != REQ_OP_WRITE) {
		bio_io_error(bio);
		return;
	}
	if (sector + (bio->bi_iter.bi_size >> PITON_SD_SECTOR_SHIFT) >
	    piton_sd_sectors) {
		bio_io_error(bio);
		return;
	}

	write = op_is_write(bio->bi_opf);
	spin_lock_irqsave(&piton_sd_lock, flags);
	bio_for_each_segment(bvec, bio, iter) {
		void *page;
		void *buffer;

		if ((bvec.bv_offset | bvec.bv_len) &
		    (PITON_SD_SECTOR_SIZE - 1)) {
			spin_unlock_irqrestore(&piton_sd_lock, flags);
			bio_io_error(bio);
			return;
		}

		page = kmap_local_page(bvec.bv_page);
		buffer = page + bvec.bv_offset;
		if (write)
			flush_dcache_page(bvec.bv_page);
		piton_sd_transfer(write, buffer, sector, bvec.bv_len);
		if (!write)
			flush_dcache_page(bvec.bv_page);
		kunmap_local(page);
		sector += bvec.bv_len >> PITON_SD_SECTOR_SHIFT;
	}
	spin_unlock_irqrestore(&piton_sd_lock, flags);

	bio_endio(bio);
}

static const struct block_device_operations piton_sd_fops = {
	.owner = THIS_MODULE,
	.submit_bio = piton_sd_submit_bio,
};

static int __init piton_sd_init(void)
{
	struct queue_limits limits = {
		.features = BLK_FEAT_SYNCHRONOUS,
		.max_hw_sectors = PITON_SD_MAX_BIO_SECTORS,
		.max_segment_size =
			PITON_SD_MAX_BIO_SECTORS * PITON_SD_SECTOR_SIZE,
		.max_segments = 1,
		.physical_block_size = PITON_SD_SECTOR_SIZE,
		.logical_block_size = PITON_SD_SECTOR_SIZE,
		.io_min = PITON_SD_SECTOR_SIZE,
	};
	u8 gpt_sector[PITON_SD_SECTOR_SIZE];
	void __iomem *probe;
	u64 backup_lba;
	int error;

	probe = ioremap(PITON_SD_BASE_ADDR, PITON_SD_SECTOR_SIZE * 2);
	if (!probe)
		return -ENOMEM;
	piton_sd_base = probe;
	piton_sd_transfer(false, gpt_sector, 1, sizeof(gpt_sector));
	iounmap(probe);
	piton_sd_base = NULL;

	if (get_unaligned_le64(gpt_sector) != PITON_SD_GPT_SIGNATURE) {
		pr_err(PITON_SD_NAME ": invalid GPT signature\n");
		return -EINVAL;
	}

	backup_lba = get_unaligned_le64(gpt_sector + PITON_SD_GPT_BACKUP_LBA);
	piton_sd_sectors = backup_lba + 1;
	if (piton_sd_sectors < PITON_SD_MIN_SECTORS ||
	    piton_sd_sectors > PITON_SD_MAX_SECTORS) {
		pr_err(PITON_SD_NAME ": invalid capacity %llu sectors\n",
		       piton_sd_sectors);
		return -EINVAL;
	}

	piton_sd_base = ioremap(PITON_SD_BASE_ADDR,
			       piton_sd_sectors << PITON_SD_SECTOR_SHIFT);
	if (!piton_sd_base)
		return -ENOMEM;

	piton_sd_major = register_blkdev(0, PITON_SD_NAME);
	if (piton_sd_major < 0) {
		error = piton_sd_major;
		goto out_unmap;
	}

	piton_sd_disk = blk_alloc_disk(&limits, NUMA_NO_NODE);
	if (IS_ERR(piton_sd_disk)) {
		error = PTR_ERR(piton_sd_disk);
		piton_sd_disk = NULL;
		goto out_unregister;
	}

	piton_sd_disk->major = piton_sd_major;
	piton_sd_disk->first_minor = 0;
	piton_sd_disk->minors = PITON_SD_MINORS;
	piton_sd_disk->fops = &piton_sd_fops;
	strscpy(piton_sd_disk->disk_name, PITON_SD_NAME, DISK_NAME_LEN);
	set_capacity(piton_sd_disk, piton_sd_sectors);

	error = add_disk(piton_sd_disk);
	if (error)
		goto out_put_disk;

	pr_info(PITON_SD_NAME ": Linux 6.12 driver, %llu sectors (%llu MiB)\n",
		piton_sd_sectors, piton_sd_sectors >> 11);
	return 0;

out_put_disk:
	put_disk(piton_sd_disk);
	piton_sd_disk = NULL;
out_unregister:
	unregister_blkdev(piton_sd_major, PITON_SD_NAME);
out_unmap:
	iounmap(piton_sd_base);
	piton_sd_base = NULL;
	return error;
}

static void __exit piton_sd_exit(void)
{
	if (piton_sd_disk) {
		del_gendisk(piton_sd_disk);
		put_disk(piton_sd_disk);
	}
	if (piton_sd_major > 0)
		unregister_blkdev(piton_sd_major, PITON_SD_NAME);
	if (piton_sd_base)
		iounmap(piton_sd_base);
}

module_init(piton_sd_init);
module_exit(piton_sd_exit);

MODULE_DESCRIPTION("OpenPiton+Ariane FPGA SD-card aperture block driver");
MODULE_LICENSE("GPL");
