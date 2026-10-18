# Pango SDC template for ARES-P4.
# System clock: 100 MHz.  The video pixel clock is divided by 4 inside
# ares_video, so no second clock domain is required in this revision.

create_clock -name sys_clk -period 10.000 [get_ports clk]
set_clock_uncertainty 0.300 [get_clocks sys_clk]
set_clock_transition 0.200 [get_clocks sys_clk]

# Inputs are asynchronous or quasi-static in this revision.
set_false_path -from [get_ports rst]
set_false_path -from [get_ports uart_rx]
set_false_path -from [get_ports gpio_in*]
set_false_path -from [get_ports spi_miso]

# Outputs: UART/SPI/GPIO are slow; HDMI TMDS is source-synchronous and must be
# constrained against the board HDMI clock once the OSERDES wrapper is added.
set_output_delay -clock sys_clk -max 3.000 [get_ports {uart_tx spi_sck spi_mosi spi_cs_n gpio_out* gpio_dir*}]
set_output_delay -clock sys_clk -min 0.000 [get_ports {uart_tx spi_sck spi_mosi spi_cs_n gpio_out* gpio_dir*}]

# The Pango DDR3 IP owns its own timing constraints.  The L2-to-DDR request
# path is synchronous to sys_clk in this wrapper.
