/*
Copyright (c) 2019 Princeton University
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Princeton University nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
#include "Vcmp_top.h"
#include "verilated.h"
#include <iostream>
#ifdef VERILATOR_VCD
#include "verilated_vcd_c.h"
#endif
#ifdef COH_IPI64_SMALL_VCD
#include "Vcmp_top___024root.h"
#include "Vcmp_top_tile__T2.h"
#include <cstddef>
#include <fstream>
#endif

uint64_t main_time = 0; // Current simulation time
uint64_t clk = 0;
Vcmp_top* top;
#ifdef VERILATOR_VCD
VerilatedVcdC* tfp;
#endif

#ifdef COH_IPI64_SMALL_VCD
#ifndef COH_IPI64_SMALL_VCD_START
#define COH_IPI64_SMALL_VCD_START 16000000ULL
#endif
#ifndef COH_IPI64_SMALL_VCD_FLUSH_PERIOD
#define COH_IPI64_SMALL_VCD_FLUSH_PERIOD 1000000ULL
#endif
#ifndef COH_IPI64_SMALL_VCD_STOP
#define COH_IPI64_SMALL_VCD_STOP 0ULL
#endif
#ifndef COH_IPI64_PROGRESS_PERIOD
#define COH_IPI64_PROGRESS_PERIOD 1000000ULL
#endif

class CohIpi64SmallVcd {
  private:
    enum Signal {
        S_CLK,
        S_SYS_RST_N,
        S_OK_IOB,
        S_CLINT_EN,
        S_CLINT_WE,
        S_CLINT_ADDR,
        S_CLINT_RDATA,
        S_CLINT_MSIP_N,
        S_CLINT_MSIP_Q,
        S_CLINT_AWVALID,
        S_CLINT_WVALID,
        S_CLINT_ARVALID,
        S_CLINT_STORE_GO,
        S_CLINT_LOAD_GO,
        S_CLINT_MSG_STATE,
        S_CLINT_MSG_TYPE,
        S_CLINT_MSG_COUNTER,
        S_CLINT_NOC2_OUT_COUNT,
        S_CLINT_NOC3_OUT_COUNT,
        S_CLINT_NOC2_IN_COUNT,
        S_CLINT_NOC3_IN_COUNT,
        S_T0_NOC2_DATA_VAL,
        S_T0_NOC2_DATA_ACK,
        S_T0_NOC2_L15_VAL,
        S_T0_NOC1_REQ_VAL,
        S_T0_NOC1_REQ_TYPE,
        S_T0_NOC1_REQ_ADDR,
        S_T0_NOC1_ENC_REQ_TYPE,
        S_T0_NOC1_ENC_MSG_TYPE,
        S_T0_NOC1_ENC_FLIT_STATE,
        S_T0_NOC1_ENC_FLIT,
        S_T0_NOC3_REQ_VAL,
        S_T0_NOC3_REQ_TYPE,
        S_T0_NOC3_REQ_WITH_DATA,
        S_T0_NOC3_REQ_ACK,
        S_T0_NOC3_BUF_WITH_DATA,
        S_T0_NOC3_ENC_MSG_TYPE,
        S_T0_NOC3_ENC_FLIT_STATE,
        S_T0_NOC3_ENC_FLIT,
        S_T0_STALL_S1,
        S_T0_STALL_S2,
        S_T0_VAL_S2,
        S_T0_VAL_S3,
        S_T0_REQTYPE_S1,
        S_T0_REQTYPE_S2,
        S_T0_REQTYPE_S3,
        S_T0_ADDR_S1,
        S_T0_ADDR_S2,
        S_T0_ADDR_S3,
        S_T0_DTAG_VAL_S1,
        S_T0_DTAG_RW_S1,
        S_T0_DTAG_INDEX_S1,
        S_T0_MESI_WRITE_VAL_S2,
        S_T0_MESI_WRITE_INDEX_S2,
        S_T0_MESI_WRITE_MASK_S2,
        S_T0_MESI_WRITE_DATA_S2,
        S_T36_NOC2_DATA_VAL,
        S_T36_NOC2_L15_VAL,
        S_T36_NOC1_REQ_VAL,
        S_T36_NOC1_REQ_TYPE,
        S_T36_NOC1_REQ_ADDR,
        S_T36_NOC3_REQ_VAL,
        S_T36_NOC3_REQ_TYPE,
        S_T36_NOC3_REQ_WITH_DATA,
        S_T36_STALL_S1,
        S_T36_STALL_S2,
        S_T36_VAL_S2,
        S_T36_VAL_S3,
        S_T36_FETCH_STATE_S1,
        S_T36_NOC1_OP_S2,
        S_T36_NOC3_OP_S3,
        S_T36_ADDR_S2,
        S_T36_ADDR_S3,
        S_T36_CSM_REQ_VAL_S2,
        S_T36_CSM_REQ_TICKET_S2,
        S_T36_CSM_REQ_TYPE_S2,
        S_T36_CSM_REQ_ADDR_S2,
        S_T36_CSM_REQ_VAL_S3,
        S_T36_CSM_REQ_TICKET_S3,
        S_T36_CSM_REQ_ADDR_S3,
        S_T36_CSM_RES_DATA_S3,
        S_T36_CSM_HIT_S3,
        S_T36_CSM_RD_EN_S3,
        S_T36_CSM_WR_EN_S3,
        S_T36_CSM_OP_S2,
        S_T36_CSM_TICKET_S2,
        S_T36_CSM_TICKET_S3,
        S_T36_CSM_PCX_DATA_S2,
        S_T36_CSM_PCX_DATA_S3,
        S_T36_NOC2_MSG_NEW,
        S_T36_NOC2_DATA_0,
        S_T36_NOC2_DATA_1,
        S_T36_NOC2_DATA_2,
        S_T36_NOC2_DATA_3,
        S_T36_NOC2_DATA_4,
        S_T36_NOC2_DATA_5,
        S_T36_NOC2_DATA_6,
        S_T36_NOC2_DATA_7,
        S_T36_NOC2_DEC_DATA1,
        S_T36_BUFFER_NOC2_DATA,
        S_T36_CSM_WRITE_VAL_S2,
        S_T36_CSM_READ_VAL_S2,
        S_T36_CSM_GHID_VAL_S2,
        S_T36_CSM_WR_EN_S2,
        S_T36_CSM_DIAG_EN_S2,
        S_T36_CSM_FLUSH_EN_S2,
        S_T36_CSM_GHID_TICKETED_VAL,
        S_T36_CSM_REQ_DATA_0,
        S_T36_CSM_REQ_DATA_1,
        S_BOOTROM_NOC2_DATA,
        S_BOOTROM_NOC2_COUNT,
        S_BOOTROM_NOC2_UP,
        S_BOOTROM_NOC2_DOWN,
        S_BOOTROM_NOC2_YUMMY,
        S_CLINT_NOC2_DATA,
        S_CLINT_NOC2_COUNT_DETAIL,
        S_CLINT_NOC2_UP,
        S_CLINT_NOC2_DOWN,
        S_CLINT_NOC2_YUMMY,
        S_NUM_SIGNALS
    };

    struct SignalInfo {
        const char* id;
        const char* name;
        int width;
    };

    std::ofstream file_;
    bool open_;
    bool emitted_time_;
    uint64_t emitted_time_value_;
    uint64_t last_flush_time_;
    uint64_t last_[S_NUM_SIGNALS];
    bool valid_[S_NUM_SIGNALS];

    static const SignalInfo& info(Signal sig) {
        static const SignalInfo infos[S_NUM_SIGNALS] = {
            {"s0",  "core_ref_clk",                  1},
            {"s1",  "sys_rst_n",                     1},
            {"s2",  "ok_iob",                        1},
            {"s3",  "clint_axi_state_q",             2},
            {"s4",  "clint_axi_state_d",             2},
            {"s5",  "clint_axi_address_q",          64},
            {"s6",  "clint_mtime_q",                64},
            {"s7",  "clint_msip_n",                 64},
            {"s8",  "clint_msip_q",                 64},
            {"s9",  "clint_axi_awvalid",             1},
            {"s10", "clint_axi_wvalid",              1},
            {"s11", "clint_axi_arvalid",             1},
            {"s12", "clint_splitter_store_go",       1},
            {"s13", "clint_splitter_load_go",        1},
            {"s14", "clint_splitter_msg_state",      3},
            {"s15", "clint_splitter_msg_type",       2},
            {"s16", "clint_splitter_msg_counter",    8},
            {"s17", "clint_noc2_out_count",          3},
            {"s18", "clint_noc3_out_count",          3},
            {"s19", "clint_noc2_in_count",           3},
            {"s20", "clint_noc3_out_valid_temp",     1},
            {"s21", "tile0_noc2_data_val",           1},
            {"s22", "tile0_noc2_msg_new",            1},
            {"s23", "tile0_noc2decoder_l15_val",     1},
            {"s24", "tile0_noc1_req_val",            1},
            {"s25", "tile0_noc1_req_type",           5},
            {"s26", "tile0_noc1_req_address",       40},
            {"s27", "tile0_noc1enc_req_type",        5},
            {"s28", "tile0_noc1enc_msg_type",        8},
            {"s29", "tile0_noc1enc_flit_state",      4},
            {"s30", "tile0_noc1enc_flit",           64},
            {"s31", "tile0_noc3_req_val",            1},
            {"s32", "tile0_noc3_req_type",           3},
            {"s33", "tile0_noc3_req_with_data",      1},
            {"s34", "tile0_noc3_req_ack",            1},
            {"s35", "tile0_noc3_buf_with_data",      1},
            {"s36", "tile0_noc3enc_msg_type",        8},
            {"s37", "tile0_noc3enc_flit_state",      4},
            {"s38", "tile0_noc3enc_data0",          64},
            {"s39", "tile0_l15_stall_s1",            1},
            {"s40", "tile0_l15_stall_s2",            1},
            {"s41", "tile0_l15_val_s2",              1},
            {"s42", "tile0_l15_val_s3",              1},
            {"s43", "tile0_l15_fetch_state_s1",      3},
            {"s44", "tile0_l15_noc1_op_s2",          5},
            {"s45", "tile0_l15_noc3_op_s3",          3},
            {"s46", "tile0_l15_predecode_index_s1",  7},
            {"s47", "tile0_l15_address_s2",         40},
            {"s48", "tile0_l15_address_s3",         40},
            {"s49", "tile0_l15_dtag_op_s2",          2},
            {"s50", "tile0_l15_lru_way_s2",          2},
            {"s51", "tile0_l15_dtag_index_s1",       7},
            {"s52", "tile0_l15_mesi_write_val_s2",   1},
            {"s53", "tile0_l15_mesi_write_index_s2", 7},
            {"s54", "tile0_l15_mesi_write_mask_s2",  8},
            {"s55", "tile0_l15_mesi_write_data_s2",  8},
            {"s56", "tile36_noc2_data_val",           1},
            {"s57", "tile36_noc2decoder_l15_val",     1},
            {"s58", "tile36_noc1_req_val",            1},
            {"s59", "tile36_noc1_req_type",           5},
            {"s60", "tile36_noc1_req_address",       40},
            {"s61", "tile36_noc3_req_val",            1},
            {"s62", "tile36_noc3_req_type",           3},
            {"s63", "tile36_noc3_req_with_data",      1},
            {"s64", "tile36_l15_stall_s1",            1},
            {"s65", "tile36_l15_stall_s2",            1},
            {"s66", "tile36_l15_val_s2",              1},
            {"s67", "tile36_l15_val_s3",              1},
            {"s68", "tile36_l15_fetch_state_s1",      3},
            {"s69", "tile36_l15_noc1_op_s2",          5},
            {"s70", "tile36_l15_noc3_op_s3",          3},
            {"s71", "tile36_l15_address_s2",         40},
            {"s72", "tile36_l15_address_s3",         40},
            {"s73", "tile36_l15_csm_req_val_s2",      1},
            {"s74", "tile36_l15_csm_req_ticket_s2",   3},
            {"s75", "tile36_l15_csm_req_type_s2",     1},
            {"s76", "tile36_l15_csm_req_address_s2", 40},
            {"s77", "tile36_l15_csm_req_val_s3",      1},
            {"s78", "tile36_l15_csm_req_ticket_s3",   3},
            {"s79", "tile36_l15_csm_req_address_s3", 40},
            {"s80", "tile36_l15_csm_res_data_s3",    64},
            {"s81", "tile36_l15_csm_hit_s3",          1},
            {"s82", "tile36_l15_csm_rd_en_s3",        1},
            {"s83", "tile36_l15_csm_wr_en_s3",        1},
            {"s84", "tile36_l15_csm_op_s2",           4},
            {"s85", "tile36_l15_csm_ticket_s2",       3},
            {"s86", "tile36_l15_csm_ticket_s3",       3},
            {"s87", "tile36_l15_csm_pcx_data_s2",    33},
            {"s88", "tile36_l15_csm_pcx_data_s3",    33},
            {"s89", "tile36_noc2_msg_new",            1},
            {"s90", "tile36_noc2_data_063_000",      64},
            {"s91", "tile36_noc2_data_127_064",      64},
            {"s92", "tile36_noc2_data_191_128",      64},
            {"s93", "tile36_noc2_data_255_192",      64},
            {"s94", "tile36_noc2_data_319_256",      64},
            {"s95", "tile36_noc2_data_383_320",      64},
            {"s96", "tile36_noc2_data_447_384",      64},
            {"s97", "tile36_noc2_data_511_448",      64},
            {"s98", "tile36_noc2decoder_l15_data_1", 64},
            {"s99", "tile36_buffer_processor_noc2",  64},
            {"s100", "tile36_l15_csm_write_val_s2",   1},
            {"s101", "tile36_l15_csm_read_val_s2",    1},
            {"s102", "tile36_l15_csm_ghid_val_s2",    1},
            {"s103", "tile36_l15_csm_wr_en_s2",       1},
            {"s104", "tile36_l15_csm_diag_en_s2",     1},
            {"s105", "tile36_l15_csm_flush_en_s2",    1},
            {"s106", "tile36_l15_csm_ghid_ticketed",  8},
            {"s107", "tile36_l15_csm_req_data_063_000", 64},
            {"s108", "tile36_l15_csm_req_data_127_064", 64},
            {"s109", "bootrom_buf_noc2_data",        64},
            {"s110", "bootrom_noc2_count",            3},
            {"s111", "bootrom_noc2_up",               1},
            {"s112", "bootrom_noc2_down",             1},
            {"s113", "bootrom_noc2_yummy",            1},
            {"s114", "clint_buf_noc2_data",          64},
            {"s115", "clint_noc2_count_detail",       3},
            {"s116", "clint_noc2_up",                 1},
            {"s117", "clint_noc2_down",               1},
            {"s118", "clint_noc2_yummy",              1},
        };
        return infos[sig];
    }

    template <std::size_t N>
    static uint64_t wide64(const VlWide<N>& value, int low_word) {
        return (static_cast<uint64_t>(value[low_word + 1]) << 32)
             | static_cast<uint64_t>(value[low_word]);
    }

    void open_file() {
        if (open_) return;
        file_.open("coh_ipi64_small.vcd");
        if (!file_) return;
        open_ = true;
        file_ << "$date\n  generated by my_top.cpp COH_IPI64_SMALL_VCD\n$end\n";
        file_ << "$version\n  OpenPiton coh_ipi64 small VCD\n$end\n";
        file_ << "$timescale 1ps $end\n";
        file_ << "$scope module coh_ipi64_small $end\n";
        for (int i = 0; i < S_NUM_SIGNALS; i++) {
            const SignalInfo& si = info(static_cast<Signal>(i));
            file_ << "$var wire " << si.width << " " << si.id << " " << si.name << " $end\n";
        }
        file_ << "$upscope $end\n";
        file_ << "$enddefinitions $end\n";
        file_.flush();
    }

    void emit_time(uint64_t time) {
        if (!emitted_time_ || emitted_time_value_ != time) {
            file_ << "#" << time << "\n";
            emitted_time_ = true;
            emitted_time_value_ = time;
        }
    }

    void emit_value(const SignalInfo& si, uint64_t value) {
        if (si.width == 1) {
            file_ << ((value & 1ULL) ? '1' : '0') << si.id << "\n";
            return;
        }
        file_ << "b";
        for (int bit = si.width - 1; bit >= 0; bit--) {
            file_ << (((value >> bit) & 1ULL) ? '1' : '0');
        }
        file_ << " " << si.id << "\n";
    }

    void sample_signal(Signal sig, uint64_t value, uint64_t time) {
        const int idx = static_cast<int>(sig);
        if (valid_[idx] && last_[idx] == value) return;
        emit_time(time);
        emit_value(info(sig), value);
        last_[idx] = value;
        valid_[idx] = true;
    }

  public:
    CohIpi64SmallVcd() : open_(false), emitted_time_(false), emitted_time_value_(0), last_flush_time_(0) {
        for (int i = 0; i < S_NUM_SIGNALS; i++) {
            last_[i] = 0;
            valid_[i] = false;
        }
    }

    ~CohIpi64SmallVcd() {
        close();
    }

    void close() {
        if (!open_) return;
        file_.flush();
        file_.close();
        open_ = false;
    }

    void sample(uint64_t time, Vcmp_top* model) {
        if (!model || !model->ok_iob || time < COH_IPI64_SMALL_VCD_START) return;
        open_file();
        if (!open_) return;

        Vcmp_top___024root* r = model->rootp;
        Vcmp_top_tile__T2* t = model->__PVT__cmp_top__DOT__system__DOT__chip__DOT__tile0;
        Vcmp_top_tile__T2* t36 = model->__PVT__cmp_top__DOT__system__DOT__chip__DOT__tile36;

        if (!valid_[S_CLK]) sample_signal(S_CLK, model->core_ref_clk, time);
        sample_signal(S_SYS_RST_N, model->sys_rst_n, time);
        sample_signal(S_OK_IOB, model->ok_iob, time);

        sample_signal(S_CLINT_EN, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint__DOT__axi_lite_interface_i__DOT__state_q, time);
        sample_signal(S_CLINT_WE, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint__DOT__axi_lite_interface_i__DOT__state_d, time);
        sample_signal(S_CLINT_ADDR, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint__DOT__axi_lite_interface_i__DOT__address_q, time);
        sample_signal(S_CLINT_RDATA, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint__DOT__mtime_q, time);
        sample_signal(S_CLINT_MSIP_N, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint__DOT__msip_n, time);
        sample_signal(S_CLINT_MSIP_Q, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint__DOT__msip_q, time);
        sample_signal(S_CLINT_AWVALID, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT____Vcellout__i_clint_axilite_bridge__m_axi_awvalid, time);
        sample_signal(S_CLINT_WVALID, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT____Vcellout__i_clint_axilite_bridge__m_axi_wvalid, time);
        sample_signal(S_CLINT_ARVALID, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT____Vcellout__i_clint_axilite_bridge__m_axi_arvalid, time);
        sample_signal(S_CLINT_STORE_GO, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint_axilite_bridge__DOT__splitter_io_store_go, time);
        sample_signal(S_CLINT_LOAD_GO, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint_axilite_bridge__DOT__splitter_io_load_go, time);
        sample_signal(S_CLINT_MSG_STATE, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint_axilite_bridge__DOT__splitter_io_msg_state_f, time);
        sample_signal(S_CLINT_MSG_TYPE, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint_axilite_bridge__DOT__splitter_io_msg_type_f, time);
        sample_signal(S_CLINT_MSG_COUNTER, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__i_riscv_peripherals__DOT__i_clint_axilite_bridge__DOT__splitter_io_msg_counter_f, time);
        sample_signal(S_CLINT_NOC2_OUT_COUNT, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_clint_to_xbar__DOT__count_f, time);
        sample_signal(S_CLINT_NOC3_OUT_COUNT, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc3_ariane_clint_to_xbar__DOT__count_f, time);
        sample_signal(S_CLINT_NOC2_IN_COUNT, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_xbar_to_ariane_clint__DOT__data__DOT__elements_in_array_f, time);
        sample_signal(S_CLINT_NOC3_IN_COUNT, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc3_ariane_clint_to_xbar__DOT__valid_temp_f, time);

        sample_signal(S_T0_NOC2_DATA_VAL, t->__PVT__l15__DOT__l15__DOT__noc2_data_val, time);
        sample_signal(S_T0_NOC2_DATA_ACK, t->__PVT__l15__DOT__l15__DOT__noc2decoder__DOT__is_message_new, time);
        sample_signal(S_T0_NOC2_L15_VAL, t->l15__DOT__l15__DOT__noc2decoder_l15_val, time);
        sample_signal(S_T0_NOC1_REQ_VAL, t->__PVT__l15__DOT__l15__DOT__l15_noc1buffer_req_val, time);
        sample_signal(S_T0_NOC1_REQ_TYPE, t->__PVT__l15__DOT__l15__DOT__l15_noc1buffer_req_type, time);
        sample_signal(S_T0_NOC1_REQ_ADDR, t->__PVT__l15__DOT__l15__DOT__l15_noc1buffer_req_address, time);
        sample_signal(S_T0_NOC1_ENC_REQ_TYPE, t->l15__DOT__l15__DOT__noc1encoder__DOT__req_type, time);
        sample_signal(S_T0_NOC1_ENC_MSG_TYPE, t->__PVT__l15__DOT__l15__DOT__noc1encoder__DOT__msg_type, time);
        sample_signal(S_T0_NOC1_ENC_FLIT_STATE, t->__PVT__l15__DOT__l15__DOT__noc1encoder__DOT__flit_state, time);
        sample_signal(S_T0_NOC1_ENC_FLIT, t->__PVT__l15__DOT__l15__DOT__noc1encoder__DOT__flit, time);
        sample_signal(S_T0_NOC3_REQ_VAL, t->__PVT__l15__DOT__l15__DOT__l15_noc3encoder_req_val, time);
        sample_signal(S_T0_NOC3_REQ_TYPE, t->__PVT__l15__DOT__l15__DOT__l15_noc3encoder_req_type, time);
        sample_signal(S_T0_NOC3_REQ_WITH_DATA, t->__PVT__l15__DOT__l15__DOT__l15_noc3encoder_req_with_data, time);
        sample_signal(S_T0_NOC3_REQ_ACK, t->__PVT__l15__DOT__l15__DOT__noc3encoder_l15_req_ack, time);
        sample_signal(S_T0_NOC3_BUF_WITH_DATA, t->l15__DOT__l15__DOT__noc3buffer__DOT__l15_noc3encoder_req_with_data_buf, time);
        sample_signal(S_T0_NOC3_ENC_MSG_TYPE, t->l15__DOT__l15__DOT__noc3encoder__DOT__msg_type, time);
        sample_signal(S_T0_NOC3_ENC_FLIT_STATE, t->__PVT__l15__DOT__l15__DOT__noc3encoder__DOT__flit_state, time);
        sample_signal(S_T0_NOC3_ENC_FLIT, t->__PVT__l15__DOT__l15__DOT__noc3encoder__DOT__l15_noc3encoder_req_data_0_f, time);
        sample_signal(S_T0_STALL_S1, t->l15__DOT__l15__DOT__pipeline__DOT__stall_s1, time);
        sample_signal(S_T0_STALL_S2, t->l15__DOT__l15__DOT__pipeline__DOT__stall_s2, time);
        sample_signal(S_T0_VAL_S2, t->l15__DOT__l15__DOT__pipeline__DOT__val_s2, time);
        sample_signal(S_T0_VAL_S3, t->l15__DOT__l15__DOT__pipeline__DOT__val_s3, time);
        sample_signal(S_T0_REQTYPE_S1, t->l15__DOT__l15__DOT__pipeline__DOT__fetch_state_s1, time);
        sample_signal(S_T0_REQTYPE_S2, t->__PVT__l15__DOT__l15__DOT__pipeline__DOT__noc1_operation_s2, time);
        sample_signal(S_T0_REQTYPE_S3, t->__PVT__l15__DOT__l15__DOT__pipeline__DOT__noc3_operations_s3, time);
        sample_signal(S_T0_ADDR_S1, t->__PVT__l15__DOT__l15__DOT__pipeline__DOT__predecode_cache_index_s1, time);
        sample_signal(S_T0_ADDR_S2, t->__PVT__l15__DOT__l15__DOT__pipeline__DOT__address_s2, time);
        sample_signal(S_T0_ADDR_S3, t->__PVT__l15__DOT__l15__DOT__pipeline__DOT__address_s3, time);
        sample_signal(S_T0_DTAG_VAL_S1, t->l15__DOT__l15__DOT__pipeline__DOT__decoder_dtag_operation_s2, time);
        sample_signal(S_T0_DTAG_RW_S1, t->l15__DOT__l15__DOT__pipeline__DOT__lru_way_s2, time);
        sample_signal(S_T0_DTAG_INDEX_S1, t->__PVT__l15__DOT__l15__DOT__l15_dtag_index_s1, time);
        sample_signal(S_T0_MESI_WRITE_VAL_S2, t->__PVT__l15__DOT__l15__DOT__l15_mesi_write_val_s2, time);
        sample_signal(S_T0_MESI_WRITE_INDEX_S2, t->__PVT__l15__DOT__l15__DOT__l15_mesi_write_index_s2, time);
        sample_signal(S_T0_MESI_WRITE_MASK_S2, t->__PVT__l15__DOT__l15__DOT__l15_mesi_write_mask_s2, time);
        sample_signal(S_T0_MESI_WRITE_DATA_S2, t->__PVT__l15__DOT__l15__DOT__l15_mesi_write_data_s2, time);

        sample_signal(S_T36_NOC2_DATA_VAL, t36->__PVT__l15__DOT__l15__DOT__noc2_data_val, time);
        sample_signal(S_T36_NOC2_L15_VAL, t36->l15__DOT__l15__DOT__noc2decoder_l15_val, time);
        sample_signal(S_T36_NOC1_REQ_VAL, t36->__PVT__l15__DOT__l15__DOT__l15_noc1buffer_req_val, time);
        sample_signal(S_T36_NOC1_REQ_TYPE, t36->__PVT__l15__DOT__l15__DOT__l15_noc1buffer_req_type, time);
        sample_signal(S_T36_NOC1_REQ_ADDR, t36->__PVT__l15__DOT__l15__DOT__l15_noc1buffer_req_address, time);
        sample_signal(S_T36_NOC3_REQ_VAL, t36->__PVT__l15__DOT__l15__DOT__l15_noc3encoder_req_val, time);
        sample_signal(S_T36_NOC3_REQ_TYPE, t36->__PVT__l15__DOT__l15__DOT__l15_noc3encoder_req_type, time);
        sample_signal(S_T36_NOC3_REQ_WITH_DATA, t36->__PVT__l15__DOT__l15__DOT__l15_noc3encoder_req_with_data, time);
        sample_signal(S_T36_STALL_S1, t36->l15__DOT__l15__DOT__pipeline__DOT__stall_s1, time);
        sample_signal(S_T36_STALL_S2, t36->l15__DOT__l15__DOT__pipeline__DOT__stall_s2, time);
        sample_signal(S_T36_VAL_S2, t36->l15__DOT__l15__DOT__pipeline__DOT__val_s2, time);
        sample_signal(S_T36_VAL_S3, t36->l15__DOT__l15__DOT__pipeline__DOT__val_s3, time);
        sample_signal(S_T36_FETCH_STATE_S1, t36->l15__DOT__l15__DOT__pipeline__DOT__fetch_state_s1, time);
        sample_signal(S_T36_NOC1_OP_S2, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__noc1_operation_s2, time);
        sample_signal(S_T36_NOC3_OP_S3, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__noc3_operations_s3, time);
        sample_signal(S_T36_ADDR_S2, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__address_s2, time);
        sample_signal(S_T36_ADDR_S3, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__address_s3, time);
        sample_signal(S_T36_CSM_REQ_VAL_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm_req_val_s2, time);
        sample_signal(S_T36_CSM_REQ_TICKET_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm_req_ticket_s2, time);
        sample_signal(S_T36_CSM_REQ_TYPE_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm_req_type_s2, time);
        sample_signal(S_T36_CSM_REQ_ADDR_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm_req_address_s2, time);
        sample_signal(S_T36_CSM_REQ_VAL_S3, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__l15_csm_req_val_s3, time);
        sample_signal(S_T36_CSM_REQ_TICKET_S3, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__l15_csm_req_ticket_s3, time);
        sample_signal(S_T36_CSM_REQ_ADDR_S3, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__l15_csm_req_address_s3, time);
        sample_signal(S_T36_CSM_RES_DATA_S3, t36->__PVT__l15__DOT__l15__DOT__csm_l15_res_data_s3, time);
        sample_signal(S_T36_CSM_HIT_S3, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__hit_s3, time);
        sample_signal(S_T36_CSM_RD_EN_S3, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__rd_en_s3, time);
        sample_signal(S_T36_CSM_WR_EN_S3, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__wr_en_s3, time);
        sample_signal(S_T36_CSM_OP_S2, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__csm_op_s2, time);
        sample_signal(S_T36_CSM_TICKET_S2, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__csm_ticket_s2, time);
        sample_signal(S_T36_CSM_TICKET_S3, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__csm_ticket_s3, time);
        sample_signal(S_T36_CSM_PCX_DATA_S2, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__csm_pcx_data_s2, time);
        sample_signal(S_T36_CSM_PCX_DATA_S3, t36->__PVT__l15__DOT__l15__DOT__pipeline__DOT__csm_pcx_data_s3, time);
        sample_signal(S_T36_NOC2_MSG_NEW, t36->__PVT__l15__DOT__l15__DOT__noc2decoder__DOT__is_message_new, time);
        sample_signal(S_T36_NOC2_DATA_0, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 0), time);
        sample_signal(S_T36_NOC2_DATA_1, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 2), time);
        sample_signal(S_T36_NOC2_DATA_2, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 4), time);
        sample_signal(S_T36_NOC2_DATA_3, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 6), time);
        sample_signal(S_T36_NOC2_DATA_4, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 8), time);
        sample_signal(S_T36_NOC2_DATA_5, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 10), time);
        sample_signal(S_T36_NOC2_DATA_6, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 12), time);
        sample_signal(S_T36_NOC2_DATA_7, wide64(t36->__PVT__l15__DOT__l15__DOT__noc2_data, 14), time);
        sample_signal(S_T36_NOC2_DEC_DATA1, t36->__PVT__l15__DOT__l15__DOT__noc2decoder_l15_data_1, time);
        sample_signal(S_T36_BUFFER_NOC2_DATA, t36->__PVT__buffer_processor_data_noc2, time);
        sample_signal(S_T36_CSM_WRITE_VAL_S2, t36->l15__DOT__l15__DOT__l15_csm__DOT__write_val_s2, time);
        sample_signal(S_T36_CSM_READ_VAL_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__read_val_s2, time);
        sample_signal(S_T36_CSM_GHID_VAL_S2, t36->l15__DOT__l15__DOT__l15_csm__DOT__ghid_val_s2, time);
        sample_signal(S_T36_CSM_WR_EN_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__wr_en_s2, time);
        sample_signal(S_T36_CSM_DIAG_EN_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__diag_en_s2, time);
        sample_signal(S_T36_CSM_FLUSH_EN_S2, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__flush_en_s2, time);
        sample_signal(S_T36_CSM_GHID_TICKETED_VAL, t36->__PVT__l15__DOT__l15__DOT__l15_csm__DOT__ghid_ticketed_cache_val, time);
        sample_signal(S_T36_CSM_REQ_DATA_0, wide64(t36->__PVT__l15__DOT__l15__DOT__l15_csm_req_data_s2, 0), time);
        sample_signal(S_T36_CSM_REQ_DATA_1, wide64(t36->__PVT__l15__DOT__l15__DOT__l15_csm_req_data_s2, 2), time);

        sample_signal(S_BOOTROM_NOC2_DATA, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__buf_ariane_bootrom_noc2_data, time);
        sample_signal(S_BOOTROM_NOC2_COUNT, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_bootrom_to_xbar__DOT__count_f, time);
        sample_signal(S_BOOTROM_NOC2_UP, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_bootrom_to_xbar__DOT__up, time);
        sample_signal(S_BOOTROM_NOC2_DOWN, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_bootrom_to_xbar__DOT__down, time);
        sample_signal(S_BOOTROM_NOC2_YUMMY, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_bootrom_to_xbar__DOT__yummy_out_f, time);
        sample_signal(S_CLINT_NOC2_DATA, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__buf_ariane_clint_noc2_data, time);
        sample_signal(S_CLINT_NOC2_COUNT_DETAIL, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_clint_to_xbar__DOT__count_f, time);
        sample_signal(S_CLINT_NOC2_UP, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_clint_to_xbar__DOT__up, time);
        sample_signal(S_CLINT_NOC2_DOWN, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_clint_to_xbar__DOT__down, time);
        sample_signal(S_CLINT_NOC2_YUMMY, r->cmp_top__DOT__system__DOT__chipset__DOT__chipset_impl__DOT__noc2_ariane_clint_to_xbar__DOT__yummy_out_f, time);

        if (time - last_flush_time_ >= COH_IPI64_SMALL_VCD_FLUSH_PERIOD) {
            file_.flush();
            last_flush_time_ = time;
        }
    }
};

static CohIpi64SmallVcd small_vcd;
#endif

extern "C" void init_jbus_model_call(char *str, int oram);

// This is a 64-bit integer to reduce wrap over issues and
// // allow modulus. You can also use a double, if you wish.
double sc_time_stamp () { // Called by $time in Verilog
return main_time; // converts to double, to match
// what SystemC does
}

void tick() {
    top->core_ref_clk = !top->core_ref_clk;
    main_time += 250;
    top->eval();
#ifdef COH_IPI64_SMALL_VCD
    static uint64_t next_progress_time = COH_IPI64_PROGRESS_PERIOD;
    if (main_time >= next_progress_time) {
        std::cout << "COH_IPI64_PROGRESS main_time=" << main_time << std::endl << std::flush;
        next_progress_time += COH_IPI64_PROGRESS_PERIOD;
    }
    small_vcd.sample(main_time, top);
    if (COH_IPI64_SMALL_VCD_STOP != 0ULL && main_time >= COH_IPI64_SMALL_VCD_STOP) {
        small_vcd.close();
        std::cout << "COH_IPI64_SMALL_VCD_STOP main_time=" << main_time << std::endl << std::flush;
        Verilated::gotFinish(true);
        return;
    }
#endif
#ifdef VERILATOR_VCD
    // Open the trace ONLY near the error window. The L1.5 monitor error fired at
    // $time(main_time) 40166000 (~80K cycles). Open at main_time 35e6 (~70K cyc)
    // to capture ~10K cycles of lead-up.
    static bool tr_open = false;
    if (!tr_open && main_time > 35000000ULL) { tfp->open("my_top.vcd"); tr_open = true; }
    if (tr_open) tfp->dump(main_time);
#endif
    top->core_ref_clk = !top->core_ref_clk;
    main_time += 250;
    top->eval();
#ifdef COH_IPI64_SMALL_VCD
    if (main_time >= next_progress_time) {
        std::cout << "COH_IPI64_PROGRESS main_time=" << main_time << std::endl << std::flush;
        next_progress_time += COH_IPI64_PROGRESS_PERIOD;
    }
    small_vcd.sample(main_time, top);
    if (COH_IPI64_SMALL_VCD_STOP != 0ULL && main_time >= COH_IPI64_SMALL_VCD_STOP) {
        small_vcd.close();
        std::cout << "COH_IPI64_SMALL_VCD_STOP main_time=" << main_time << std::endl << std::flush;
        Verilated::gotFinish(true);
        return;
    }
#endif
#ifdef VERILATOR_VCD
    if (tr_open) tfp->dump(main_time);
#endif
}

void reset_and_init() {
    
//    fail_flag = 1'b0;
//    stub_done = 4'b0;
//    stub_pass = 4'b0;

//    // Clocks initial value
    top->core_ref_clk = 0;

//    // Resets are held low at start of boot
    top->sys_rst_n = 0;
    top->pll_rst_n = 0;

    top->ok_iob = 0;

//    // Mostly DC signals set at start of boot
//    clk_en = 1'b0;
    top->pll_bypass = 1; // trin: pll_bypass is a switch in the pll; not reliable
    top->clk_mux_sel = 0; // selecting ref clock
//    // rangeA = x10 ? 5'b1 : x5 ? 5'b11110 : x2 ? 5'b10100 : x1 ? 5'b10010 : x20 ? 5'b0 : 5'b1;
    top->pll_rangea = 1; // 10x ref clock
//    // pll_rangea = 5'b11110; // 5x ref clock
//    // pll_rangea = 5'b00000; // 20x ref clock
    
//    // JTAG simulation currently not supported here
//    jtag_modesel = 1'b1;
//    jtag_datain = 1'b0;

    top->async_mux = 0;

    init_jbus_model_call((char *) "mem.image", 0);

    std::cout << "Before first ticks" << std::endl << std::flush;
    tick();
    std::cout << "After very first tick" << std::endl << std::flush;
//    // Reset PLL for 100 cycles
//    repeat(100)@(posedge core_ref_clk);
//    pll_rst_n = 1'b1;
    for (int i = 0; i < 100; i++) {
        tick();
    }
    top->pll_rst_n = 1;

    std::cout << "Before second ticks" << std::endl << std::flush;
//    // Wait for PLL lock
//    wait( pll_lock == 1'b1 );
    while (!top->pll_lock) {
        tick();
    }

    std::cout << "Before third ticks" << std::endl << std::flush;
//    // After 10 cycles turn on chip-level clock enable
//    repeat(10)@(posedge `CHIP_INT_CLK);
//    clk_en = 1'b1;
    for (int i = 0; i < 10; i++) {
        tick();
    }
    top->clk_en = 1;

//    // After 100 cycles release reset
//    repeat(100)@(posedge `CHIP_INT_CLK);
//    sys_rst_n = 1'b1;
//    jtag_rst_l = 1'b1;
    for (int i = 0; i < 100; i++) {
        tick();
    }
    top->sys_rst_n = 1;

//    // Wait for SRAM init, trin: 5000 cycles is about the lowest
//    repeat(5000)@(posedge `CHIP_INT_CLK);
    for (int i = 0; i < 5000; i++) {
        tick();
    }

//    top->diag_done = 1;

    //top->ciop_fake_iob.ok_iob = 1;
    top->ok_iob = 1;
    std::cout << "Reset complete" << std::endl << std::flush;
}

int main(int argc, char **argv, char **env) {
std::cout << "Started" << std::endl << std::flush;
Verilated::commandArgs(argc, argv);
top = new Vcmp_top;
std::cout << "Vcmp_top created" << std::endl << std::flush;

#ifdef VERILATOR_VCD
Verilated::traceEverOn(true);
tfp = new VerilatedVcdC;
top->trace (tfp, 99);
// do NOT open here; tick() opens it near the error window (cycle ~40.1M,
// main_time ~= 40.1e6*500 = 2.005e10) to keep the VCD small. The error
// observed: "40166000 L15 TILE0 ... L15_REQTYPE_STORE @0x8020e9c".
//tfp->open ("my_top.vcd");

Verilated::debug(1);
#endif

reset_and_init();

while (!Verilated::gotFinish()) { tick(); }

#ifdef VERILATOR_VCD
std::cout << "Trace done" << std::endl;
tfp->close();
#endif
#ifdef COH_IPI64_SMALL_VCD
small_vcd.close();
#endif

delete top;
exit(0);
}
