`timescale 1ns/1ps
`include "uvm_macros.svh"

interface dma_axi_if (
    input logic clk
);

    logic rst_n;

    logic [4:0] s_axi_awaddr;
    logic s_axi_awvalid;
    logic s_axi_awready;

    logic [31:0] s_axi_wdata;
    logic s_axi_wvalid;
    logic s_axi_wready;

    logic [1:0] s_axi_bresp;
    logic s_axi_bvalid;
    logic s_axi_bready;

    logic [4:0] s_axi_araddr;
    logic s_axi_arvalid;
    logic s_axi_arready;

    logic [31:0] s_axi_rdata;
    logic [1:0] s_axi_rresp;
    logic s_axi_rvalid;
    logic s_axi_rready;

    logic [31:0] src_addr_reg;
    logic [31:0] dst_addr_reg;
    logic [31:0] length_reg;

    logic start;
    logic busy;
    logic done;

endinterface


package dma_axi_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum {
        AXI_WRITE,
        AXI_READ
    } axi_op_e;


    class axi_item extends uvm_sequence_item;

        rand axi_op_e op;
        rand bit [4:0] addr;
        rand bit [31:0] data;

        bit [31:0] read_data;
        bit [1:0] response;

        `uvm_object_utils_begin(axi_item)
            `uvm_field_enum(axi_op_e, op, UVM_ALL_ON)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(read_data, UVM_ALL_ON)
            `uvm_field_int(response, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi_item");
            super.new(name);
        endfunction

    endclass


    class axi_sequence extends uvm_sequence #(axi_item);

        `uvm_object_utils(axi_sequence)

        function new(string name = "axi_sequence");
            super.new(name);
        endfunction


        task send_write(
            bit [4:0] addr,
            bit [31:0] data
        );

            axi_item req;

            req =
                axi_item::type_id::create(
                    "write_req"
                );

            start_item(req);

            req.op = AXI_WRITE;
            req.addr = addr;
            req.data = data;

            finish_item(req);

        endtask


        task send_read(
            bit [4:0] addr
        );

            axi_item req;

            req =
                axi_item::type_id::create(
                    "read_req"
                );

            start_item(req);

            req.op = AXI_READ;
            req.addr = addr;

            finish_item(req);

        endtask


        task body();

            bit [31:0] src;
            bit [31:0] dst;
            bit [31:0] len;

            src = $urandom;
            dst = $urandom;
            len = $urandom_range(1, 1024);

            send_write(5'h00, src);
            send_write(5'h04, dst);
            send_write(5'h08, len);

            send_read(5'h00);
            send_read(5'h04);
            send_read(5'h08);

            send_write(5'h0C, 32'h00000001);

            repeat (10) begin

                src = $urandom;
                dst = $urandom;
                len = $urandom_range(1, 4096);

                send_write(5'h00, src);
                send_write(5'h04, dst);
                send_write(5'h08, len);

                send_read(5'h00);
                send_read(5'h04);
                send_read(5'h08);

            end

        endtask

    endclass


    class axi_driver extends uvm_driver #(axi_item);

        `uvm_component_utils(axi_driver)

        virtual dma_axi_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            if (!uvm_config_db#(
                virtual dma_axi_if
            )::get(
                this,
                "",
                "vif",
                vif
            ))
                `uvm_fatal("NOVIF", "Interface not found")

        endfunction


        task run_phase(uvm_phase phase);

            axi_item req;

            vif.s_axi_awvalid = 0;
            vif.s_axi_wvalid = 0;
            vif.s_axi_bready = 0;

            vif.s_axi_arvalid = 0;
            vif.s_axi_rready = 0;

            wait(vif.rst_n);

            forever begin

                seq_item_port.get_next_item(req);

                if (req.op == AXI_WRITE)
                    drive_write(req);

                else
                    drive_read(req);

                seq_item_port.item_done();

            end

        endtask


        task drive_write(axi_item req);

            @(negedge vif.clk);

            vif.s_axi_awaddr = req.addr;
            vif.s_axi_awvalid = 1;

            vif.s_axi_wdata = req.data;
            vif.s_axi_wvalid = 1;

            vif.s_axi_bready = 1;

            do
                @(posedge vif.clk);
            while (!(vif.s_axi_awready &&
                     vif.s_axi_wready));

            @(negedge vif.clk);

            vif.s_axi_awvalid = 0;
            vif.s_axi_wvalid = 0;

            do
                @(posedge vif.clk);
            while (!vif.s_axi_bvalid);

            @(negedge vif.clk);

            vif.s_axi_bready = 0;

        endtask


        task drive_read(axi_item req);

            @(negedge vif.clk);

            vif.s_axi_araddr = req.addr;
            vif.s_axi_arvalid = 1;
            vif.s_axi_rready = 1;

            do
                @(posedge vif.clk);
            while (!vif.s_axi_arready);

            @(negedge vif.clk);

            vif.s_axi_arvalid = 0;

            do
                @(posedge vif.clk);
            while (!vif.s_axi_rvalid);

            @(negedge vif.clk);

            vif.s_axi_rready = 0;

        endtask

    endclass


    class axi_monitor extends uvm_monitor;

        `uvm_component_utils(axi_monitor)

        virtual dma_axi_if vif;

        uvm_analysis_port #(axi_item) ap;

        bit [4:0] pending_write_addr;
        bit [31:0] pending_write_data;
        bit write_pending;

        bit [4:0] pending_read_addr;
        bit read_pending;

        function new(string name, uvm_component parent);

            super.new(name, parent);

            ap = new("ap", this);

        endfunction


        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            if (!uvm_config_db#(
                virtual dma_axi_if
            )::get(
                this,
                "",
                "vif",
                vif
            ))
                `uvm_fatal("NOVIF", "Interface not found")

        endfunction


        task run_phase(uvm_phase phase);

            write_pending = 0;
            read_pending = 0;

            forever begin

                @(posedge vif.clk);

                if (!vif.rst_n) begin

                    write_pending = 0;
                    read_pending = 0;

                end

                else begin

                    if (
                        vif.s_axi_awvalid &&
                        vif.s_axi_awready &&
                        vif.s_axi_wvalid &&
                        vif.s_axi_wready
                    ) begin

                        pending_write_addr =
                            vif.s_axi_awaddr;

                        pending_write_data =
                            vif.s_axi_wdata;

                        write_pending = 1;

                    end


                    if (
                        vif.s_axi_bvalid &&
                        vif.s_axi_bready &&
                        write_pending
                    ) begin

                        axi_item t;

                        t =
                            axi_item::type_id::create(
                                "write_monitor_item"
                            );

                        t.op = AXI_WRITE;
                        t.addr = pending_write_addr;
                        t.data = pending_write_data;
                        t.response = vif.s_axi_bresp;

                        ap.write(t);

                        write_pending = 0;

                    end


                    if (
                        vif.s_axi_arvalid &&
                        vif.s_axi_arready
                    ) begin

                        pending_read_addr =
                            vif.s_axi_araddr;

                        read_pending = 1;

                    end


                    if (
                        vif.s_axi_rvalid &&
                        vif.s_axi_rready &&
                        read_pending
                    ) begin

                        axi_item t;

                        t =
                            axi_item::type_id::create(
                                "read_monitor_item"
                            );

                        t.op = AXI_READ;
                        t.addr = pending_read_addr;
                        t.read_data = vif.s_axi_rdata;
                        t.response = vif.s_axi_rresp;

                        ap.write(t);

                        read_pending = 0;

                    end

                end

            end

        endtask

    endclass


    class axi_scoreboard extends uvm_scoreboard;

        `uvm_component_utils(axi_scoreboard)

        uvm_analysis_imp #(axi_item, axi_scoreboard)
            analysis_export;

        bit [31:0] src_model;
        bit [31:0] dst_model;
        bit [31:0] length_model;

        function new(
            string name,
            uvm_component parent
        );

            super.new(name, parent);

            analysis_export =
                new(
                    "analysis_export",
                    this
                );

        endfunction


        function void write(axi_item t);

            bit [31:0] expected;

            if (t.response != 2'b00)
                `uvm_error(
                    "AXI",
                    $sformatf(
                        "Unexpected AXI response %b",
                        t.response
                    )
                )


            if (t.op == AXI_WRITE) begin

                case (t.addr)

                    5'h00:
                        src_model = t.data;

                    5'h04:
                        dst_model = t.data;

                    5'h08:
                        length_model = t.data;

                endcase

            end


            else begin

                case (t.addr)

                    5'h00:
                        expected = src_model;

                    5'h04:
                        expected = dst_model;

                    5'h08:
                        expected = length_model;

                    default:
                        expected = t.read_data;

                endcase


                if (
                    t.addr == 5'h00 ||
                    t.addr == 5'h04 ||
                    t.addr == 5'h08
                ) begin

                    if (t.read_data !== expected)

                        `uvm_error(
                            "AXI",
                            $sformatf(
                                "Address 0x%0h expected 0x%08h got 0x%08h",
                                t.addr,
                                expected,
                                t.read_data
                            )
                        )

                    else

                        `uvm_info(
                            "AXI",
                            $sformatf(
                                "PASS address=0x%0h data=0x%08h",
                                t.addr,
                                t.read_data
                            ),
                            UVM_LOW
                        )

                end

            end

        endfunction

    endclass


    class axi_agent extends uvm_agent;

        `uvm_component_utils(axi_agent)

        uvm_sequencer #(axi_item) sequencer;
        axi_driver driver;
        axi_monitor monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            sequencer =
                uvm_sequencer#(axi_item)::type_id::create(
                    "sequencer",
                    this
                );

            driver =
                axi_driver::type_id::create(
                    "driver",
                    this
                );

            monitor =
                axi_monitor::type_id::create(
                    "monitor",
                    this
                );

        endfunction

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            driver.seq_item_port.connect(
                sequencer.seq_item_export
            );

        endfunction

    endclass


    class axi_env extends uvm_env;

        `uvm_component_utils(axi_env)

        axi_agent agent;
        axi_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            agent =
                axi_agent::type_id::create(
                    "agent",
                    this
                );

            scoreboard =
                axi_scoreboard::type_id::create(
                    "scoreboard",
                    this
                );

        endfunction

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            agent.monitor.ap.connect(
                scoreboard.analysis_export
            );

        endfunction

    endclass


    class axi_test extends uvm_test;

        `uvm_component_utils(axi_test)

        axi_env env;

        function new(
            string name,
            uvm_component parent
        );

            super.new(name, parent);

        endfunction

        function void build_phase(
            uvm_phase phase
        );

            super.build_phase(phase);

            env =
                axi_env::type_id::create(
                    "env",
                    this
                );

        endfunction


        task run_phase(
            uvm_phase phase
        );

            axi_sequence seq;

            phase.raise_objection(this);

            seq =
                axi_sequence::type_id::create(
                    "seq"
                );

            seq.start(
                env.agent.sequencer
            );

            #100ns;

            phase.drop_objection(this);

        endtask

    endclass

endpackage


module dma_axi_uvm_tb;

    import uvm_pkg::*;
    import dma_axi_uvm_pkg::*;

    logic clk;

    dma_axi_if vif(clk);

    dma_axi_lite_regs dut (
        .clk(clk),
        .rst_n(vif.rst_n),

        .s_axi_awaddr(vif.s_axi_awaddr),
        .s_axi_awvalid(vif.s_axi_awvalid),
        .s_axi_awready(vif.s_axi_awready),

        .s_axi_wdata(vif.s_axi_wdata),
        .s_axi_wvalid(vif.s_axi_wvalid),
        .s_axi_wready(vif.s_axi_wready),

        .s_axi_bresp(vif.s_axi_bresp),
        .s_axi_bvalid(vif.s_axi_bvalid),
        .s_axi_bready(vif.s_axi_bready),

        .s_axi_araddr(vif.s_axi_araddr),
        .s_axi_arvalid(vif.s_axi_arvalid),
        .s_axi_arready(vif.s_axi_arready),

        .s_axi_rdata(vif.s_axi_rdata),
        .s_axi_rresp(vif.s_axi_rresp),
        .s_axi_rvalid(vif.s_axi_rvalid),
        .s_axi_rready(vif.s_axi_rready),

        .src_addr_reg(vif.src_addr_reg),
        .dst_addr_reg(vif.dst_addr_reg),
        .length_reg(vif.length_reg),

        .start(vif.start),
        .busy(vif.busy),
        .done(vif.done)
    );

    initial begin

        clk = 0;

        forever #5 clk = ~clk;

    end


    initial begin

        vif.rst_n = 0;

        vif.busy = 0;
        vif.done = 0;

        vif.s_axi_awaddr = 0;
        vif.s_axi_awvalid = 0;

        vif.s_axi_wdata = 0;
        vif.s_axi_wvalid = 0;

        vif.s_axi_bready = 0;

        vif.s_axi_araddr = 0;
        vif.s_axi_arvalid = 0;

        vif.s_axi_rready = 0;

        #30;

        vif.rst_n = 1;

    end


    initial begin

        uvm_config_db#(
            virtual dma_axi_if
        )::set(
            null,
            "*",
            "vif",
            vif
        );

        run_test("axi_test");

    end

endmodule
