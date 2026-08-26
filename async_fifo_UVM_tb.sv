`timescale 1ns/1ps
`include "uvm_macros.svh"

interface async_fifo_if #(
    parameter DATA_WIDTH = 32
)(
    input logic wr_clk,
    input logic rd_clk
);

    logic rst_n;
    logic w_en;
    logic r_en;
    logic [DATA_WIDTH-1:0] data_in;
    logic [DATA_WIDTH-1:0] data_out;
    logic empty;
    logic full;

endinterface


package async_fifo_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter DATA_WIDTH = 32;
    parameter DEPTH = 8;

    typedef enum {FIFO_WRITE, FIFO_READ} fifo_op_e;


    class fifo_item extends uvm_sequence_item;

        rand fifo_op_e op;
        rand bit [DATA_WIDTH-1:0] data;

        `uvm_object_utils_begin(fifo_item)
            `uvm_field_enum(fifo_op_e, op, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "fifo_item");
            super.new(name);
        endfunction

    endclass


    class fifo_sequence extends uvm_sequence #(fifo_item);

        `uvm_object_utils(fifo_sequence)

        function new(string name = "fifo_sequence");
            super.new(name);
        endfunction

        task body();

            fifo_item req;
            int n;

            repeat (4) begin

                n = $urandom_range(1, DEPTH);

                repeat (n) begin
                    req = fifo_item::type_id::create("req");
                    start_item(req);
                    assert(req.randomize() with { op == FIFO_WRITE; });
                    finish_item(req);
                end

                repeat (n) begin
                    req = fifo_item::type_id::create("req");
                    start_item(req);
                    assert(req.randomize() with { op == FIFO_READ; });
                    finish_item(req);
                end

            end

            repeat (DEPTH) begin
                req = fifo_item::type_id::create("req");
                start_item(req);
                assert(req.randomize() with { op == FIFO_WRITE; });
                finish_item(req);
            end

            repeat (DEPTH) begin
                req = fifo_item::type_id::create("req");
                start_item(req);
                assert(req.randomize() with { op == FIFO_READ; });
                finish_item(req);
            end

        endtask

    endclass


    class fifo_driver extends uvm_driver #(fifo_item);

        `uvm_component_utils(fifo_driver)

        virtual async_fifo_if #(DATA_WIDTH) vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db#(
                virtual async_fifo_if #(DATA_WIDTH)
            )::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Interface not found")

        endfunction

        task run_phase(uvm_phase phase);

            fifo_item req;

            vif.w_en = 0;
            vif.r_en = 0;
            vif.data_in = 0;

            wait(vif.rst_n);

            forever begin

                seq_item_port.get_next_item(req);

                if (req.op == FIFO_WRITE) begin

                    while (vif.full)
                        @(posedge vif.wr_clk);

                    @(negedge vif.wr_clk);

                    vif.data_in = req.data;
                    vif.w_en = 1;

                    @(posedge vif.wr_clk);
                    @(negedge vif.wr_clk);

                    vif.w_en = 0;

                end

                else begin

                    while (vif.empty)
                        @(posedge vif.rd_clk);

                    @(negedge vif.rd_clk);

                    vif.r_en = 1;

                    @(posedge vif.rd_clk);
                    @(negedge vif.rd_clk);

                    vif.r_en = 0;

                end

                seq_item_port.item_done();

            end

        endtask

    endclass


    class fifo_monitor extends uvm_monitor;

        `uvm_component_utils(fifo_monitor)

        virtual async_fifo_if #(DATA_WIDTH) vif;

        uvm_analysis_port #(fifo_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db#(
                virtual async_fifo_if #(DATA_WIDTH)
            )::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Interface not found")

        endfunction

        task run_phase(uvm_phase phase);

            fork

                forever begin

                    fifo_item t;

                    @(posedge vif.wr_clk);

                    if (vif.rst_n && vif.w_en && !vif.full) begin

                        t = fifo_item::type_id::create("write_item");

                        t.op = FIFO_WRITE;
                        t.data = vif.data_in;

                        ap.write(t);

                    end

                end


                forever begin

                    fifo_item t;

                    @(posedge vif.rd_clk);

                    if (vif.rst_n && vif.r_en && !vif.empty) begin

                        #1ps;

                        t = fifo_item::type_id::create("read_item");

                        t.op = FIFO_READ;
                        t.data = vif.data_out;

                        ap.write(t);

                    end

                end

            join

        endtask

    endclass


    class fifo_scoreboard extends uvm_scoreboard;

        `uvm_component_utils(fifo_scoreboard)

        uvm_analysis_imp #(fifo_item, fifo_scoreboard) analysis_export;

        bit [DATA_WIDTH-1:0] model_queue[$];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            analysis_export = new("analysis_export", this);
        endfunction

        function void write(fifo_item t);

            bit [DATA_WIDTH-1:0] expected;

            if (t.op == FIFO_WRITE) begin

                model_queue.push_back(t.data);

            end

            else begin

                if (model_queue.size() == 0) begin

                    `uvm_error("FIFO", "Read occurred with empty reference queue")

                end

                else begin

                    expected = model_queue.pop_front();

                    if (t.data !== expected)
                        `uvm_error(
                            "FIFO",
                            $sformatf(
                                "Expected %0d, got %0d",
                                expected,
                                t.data
                            )
                        )

                    else
                        `uvm_info(
                            "FIFO",
                            $sformatf(
                                "PASS expected=%0d actual=%0d",
                                expected,
                                t.data
                            ),
                            UVM_LOW
                        )

                end

            end

        endfunction

    endclass


    class fifo_agent extends uvm_agent;

        `uvm_component_utils(fifo_agent)

        uvm_sequencer #(fifo_item) sequencer;
        fifo_driver driver;
        fifo_monitor monitor;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            sequencer =
                uvm_sequencer#(fifo_item)::type_id::create(
                    "sequencer",
                    this
                );

            driver =
                fifo_driver::type_id::create(
                    "driver",
                    this
                );

            monitor =
                fifo_monitor::type_id::create(
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


    class fifo_env extends uvm_env;

        `uvm_component_utils(fifo_env)

        fifo_agent agent;
        fifo_scoreboard scoreboard;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            agent =
                fifo_agent::type_id::create(
                    "agent",
                    this
                );

            scoreboard =
                fifo_scoreboard::type_id::create(
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


    class fifo_test extends uvm_test;

        `uvm_component_utils(fifo_test)

        fifo_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            env =
                fifo_env::type_id::create(
                    "env",
                    this
                );

        endfunction

        task run_phase(uvm_phase phase);

            fifo_sequence seq;

            phase.raise_objection(this);

            seq =
                fifo_sequence::type_id::create(
                    "seq"
                );

            seq.start(env.agent.sequencer);

            #100ns;

            phase.drop_objection(this);

        endtask

    endclass

endpackage


module async_fifo_uvm_tb;

    import uvm_pkg::*;
    import async_fifo_uvm_pkg::*;

    logic wr_clk;
    logic rd_clk;

    async_fifo_if #(DATA_WIDTH) vif (
        .wr_clk(wr_clk),
        .rd_clk(rd_clk)
    );

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .PTR_WIDTH(4)
    ) dut (
        .wr_clk(vif.wr_clk),
        .rd_clk(vif.rd_clk),
        .rst_n(vif.rst_n),
        .w_en(vif.w_en),
        .r_en(vif.r_en),
        .data_in(vif.data_in),
        .data_out(vif.data_out),
        .empty(vif.empty),
        .full(vif.full)
    );

    initial begin
        wr_clk = 0;
        forever #5 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 0;
        forever #7 rd_clk = ~rd_clk;
    end

    initial begin
        vif.rst_n = 0;
        vif.w_en = 0;
        vif.r_en = 0;
        vif.data_in = 0;

        #30;

        vif.rst_n = 1;
    end

    initial begin

        uvm_config_db#(
            virtual async_fifo_if #(DATA_WIDTH)
        )::set(
            null,
            "*",
            "vif",
            vif
        );

        run_test("fifo_test");

    end

endmodule
