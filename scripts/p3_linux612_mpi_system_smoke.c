// SPDX-License-Identifier: MIT
/*
 * Board-side system-call smoke test for the P3 Linux MPI/OpenMP baseline.
 * This validates kernel facilities; it is not an MPI implementation test.
 */

#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <mqueue.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int failures;

#define CHECK(condition, label)                                                \
	do {                                                                   \
		if (condition)                                                  \
			printf("P3_MPI_SYS PASS %s\\n", label);                 \
		else {                                                         \
			printf("P3_MPI_SYS FAIL %s errno=%d\\n", label, errno); \
			failures++;                                               \
		}                                                              \
	} while (0)

static atomic_int thread_counter;

static void *thread_worker(void *unused)
{
	(void)unused;
	atomic_fetch_add_explicit(&thread_counter, 1, memory_order_relaxed);
	return NULL;
}

static void test_pthread(void)
{
	pthread_t thread;
	int error = pthread_create(&thread, NULL, thread_worker, NULL);

	if (!error)
		error = pthread_join(thread, NULL);
	CHECK(!error && atomic_load(&thread_counter) == 1, "pthread_futex");
}

static void test_shared_mmap(void)
{
	volatile int *shared = mmap(NULL, 4096, PROT_READ | PROT_WRITE,
				    MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	pid_t child;
	int status = 0;

	if (shared == MAP_FAILED) {
		CHECK(0, "shared_mmap_fork");
		return;
	}
	child = fork();
	if (!child) {
		*shared = 0x612;
		_exit(0);
	}
	if (child > 0)
		waitpid(child, &status, 0);
	CHECK(child > 0 && WIFEXITED(status) && *shared == 0x612,
	      "shared_mmap_fork");
	munmap((void *)shared, 4096);
}

static void test_posix_mqueue(void)
{
	const char *name = "/p3_mpi_smoke";
	const char payload[] = "mq";
	char received[8] = { 0 };
	struct mq_attr attr = {
		.mq_maxmsg = 4,
		.mq_msgsize = sizeof(received),
	};
	mqd_t queue;
	int ok;

	mq_unlink(name);
	queue = mq_open(name, O_CREAT | O_EXCL | O_RDWR, 0600, &attr);
	ok = queue != (mqd_t)-1;
	if (ok)
		ok = mq_send(queue, payload, sizeof(payload), 0) == 0;
	if (ok)
		ok = mq_receive(queue, received, sizeof(received), NULL) ==
		     (ssize_t)sizeof(payload);
	CHECK(ok && !memcmp(payload, received, sizeof(payload)), "posix_mqueue");
	if (queue != (mqd_t)-1)
		mq_close(queue);
	mq_unlink(name);
}

static void test_unix_socket(void)
{
	int pair[2] = { -1, -1 };
	char byte = 'U';
	char received = 0;
	int ok = socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0;

	if (ok)
		ok = write(pair[0], &byte, 1) == 1;
	if (ok)
		ok = read(pair[1], &received, 1) == 1;
	CHECK(ok && received == byte, "unix_socket");
	if (pair[0] >= 0)
		close(pair[0]);
	if (pair[1] >= 0)
		close(pair[1]);
}

static void test_tcp_loopback(void)
{
	struct sockaddr_in address = {
		.sin_family = AF_INET,
		.sin_addr.s_addr = htonl(INADDR_LOOPBACK),
	};
	socklen_t length = sizeof(address);
	int listener = -1;
	int client = -1;
	int accepted = -1;
	int ok = 0;

	listener = socket(AF_INET, SOCK_STREAM, 0);
	if (listener < 0)
		goto out;
	if (bind(listener, (struct sockaddr *)&address, sizeof(address)) ||
	    getsockname(listener, (struct sockaddr *)&address, &length) ||
	    listen(listener, 1))
		goto out;
	client = socket(AF_INET, SOCK_STREAM, 0);
	if (client < 0 ||
	    connect(client, (struct sockaddr *)&address, sizeof(address)))
		goto out;
	accepted = accept(listener, NULL, NULL);
	ok = accepted >= 0;
out:
	CHECK(ok, "tcp_loopback");
	if (accepted >= 0)
		close(accepted);
	if (client >= 0)
		close(client);
	if (listener >= 0)
		close(listener);
}

int main(void)
{
	cpu_set_t cpus;
	struct timespec now;
	long online = sysconf(_SC_NPROCESSORS_ONLN);
	int affinity_ok;

	printf("P3_MPI_SYS START online=%ld\\n", online);
	CPU_ZERO(&cpus);
	affinity_ok = sched_getaffinity(0, sizeof(cpus), &cpus) == 0;
	CHECK(online >= 1 && affinity_ok && CPU_COUNT(&cpus) >= 1,
	      "cpu_affinity");
	CHECK(clock_gettime(CLOCK_MONOTONIC, &now) == 0, "clock_monotonic");
	test_pthread();
	test_shared_mmap();
	test_posix_mqueue();
	test_unix_socket();
	test_tcp_loopback();
	if (failures)
		printf("P3_MPI_SYS FAILED failures=%d\\n", failures);
	else
		printf("P3_MPI_SYS ALL_PASS failures=0\\n");
	return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
