--------------------------------------------------------------------------------
-- uart_to_rgmii_bridge
--
-- Bridges UART RX bytes into an RGMII TX nibble stream. Bytes are written
-- into a dual-clock FIFO from the UART side; on the RGMII side an idle
-- timeout on the write port triggers a burst read, the bytes are split into
-- nibbles and emitted via DDIO output cells.
--
-- Notes:
--   * rst is active high (synchronous in each clock domain). The 'aclr' inputs
--     of the DDIO megacells take rst directly.
--   * This module is currently not instantiated by top.vhd; the live data path
--     uses a plain dual-clock FIFO. Kept here for future re-integration.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_to_rgmii_bridge is
    port (
        -- Reset (active high)
        rst          : in  std_logic;

        -- UART / write domain (slow, e.g. 100 MHz)
        uart_clk     : in  std_logic;
        uart_data    : in  std_logic_vector(7 downto 0);
        uart_valid   : in  std_logic;

        -- RGMII / read domain (must be 125 MHz for 1 Gbps)
        rgmii_clk    : in  std_logic;

        -- RGMII PHY-side outputs
        rgmii_txd    : out std_logic_vector(3 downto 0);
        rgmii_tx_ctl : out std_logic;
        rgmii_txc    : out std_logic
    );
end entity uart_to_rgmii_bridge;

architecture rtl of uart_to_rgmii_bridge is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------
    constant TIMEOUT_CYCLES : integer := 5000;

    ----------------------------------------------------------------------------
    -- FIFO interface
    ----------------------------------------------------------------------------
    signal fifo_q        : std_logic_vector(7 downto 0);
    signal fifo_rdreq    : std_logic;
    signal fifo_rdreq_d1 : std_logic;
    signal fifo_rdreq_d2 : std_logic;
    signal fifo_empty    : std_logic;
    signal fifo_rdusedw  : std_logic_vector(8 downto 0);

    ----------------------------------------------------------------------------
    -- Write-side timeout trigger
    ----------------------------------------------------------------------------
    signal idle_counter : unsigned(15 downto 0);
    signal write_active : std_logic := '0';
    signal timeout_en   : std_logic := '0';

    ----------------------------------------------------------------------------
    -- CDC into RGMII clock domain
    ----------------------------------------------------------------------------
    signal timeout_en_sync_d1   : std_logic := '0';
    signal timeout_en_sync_d2   : std_logic := '0';
    signal timeout_en_sync_d3   : std_logic := '0';
    signal timeout_en_pulse     : std_logic := '0';  -- one-cycle on rising edge

    ----------------------------------------------------------------------------
    -- Data path
    ----------------------------------------------------------------------------
    signal ethernet_data     : std_logic_vector(7 downto 0);
    signal ddrio_in_h        : std_logic_vector(3 downto 0);
    signal ddrio_in_l        : std_logic_vector(3 downto 0);
    signal tx_enable         : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- Dual-clock FIFO
    ----------------------------------------------------------------------------
    uart_sync_fifo_inst : entity work.uart_sync_fifo
        port map (
            wrclk   => uart_clk,
            data    => uart_data,
            wrreq   => uart_valid,
            rdclk   => rgmii_clk,
            rdreq   => fifo_rdreq,
            q       => fifo_q,
            wrempty => fifo_empty,
            rdusedw => fifo_rdusedw,
            wrfull  => open
        );

    ----------------------------------------------------------------------------
    -- write_timeout
    --
    -- Counts UART idle cycles after the last valid byte. When the count
    -- reaches TIMEOUT_CYCLES (and the FIFO is non-empty), raises timeout_en
    -- to tell the RGMII side to drain the FIFO.
    ----------------------------------------------------------------------------
    write_timeout : process (uart_clk, rst)
    begin
        if rst = '1' then
            idle_counter <= (others => '0');
            write_active <= '0';
            timeout_en   <= '0';
        elsif rising_edge(uart_clk) then
            if uart_valid = '1' then
                idle_counter <= (others => '0');
                write_active <= '1';
                timeout_en   <= '0';
            else
                write_active <= '0';
                if idle_counter < TIMEOUT_CYCLES then
                    if fifo_empty = '0' then
                        idle_counter <= idle_counter + 1;
                    end if;
                else
                    timeout_en <= '1';
                end if;
            end if;
        end if;
    end process write_timeout;

    ----------------------------------------------------------------------------
    -- read_control
    --
    -- 3-stage CDC + rising-edge detector on timeout_en. On the pulse, asserts
    -- fifo_rdreq; deasserts when only two words remain in the FIFO. The data
    -- path is one cycle behind the read enable to match FIFO read latency.
    ----------------------------------------------------------------------------
    read_control : process (rgmii_clk, rst)
    begin
        if rst = '1' then
            fifo_rdreq          <= '0';
            fifo_rdreq_d1       <= '0';
            fifo_rdreq_d2       <= '0';
            timeout_en_sync_d1  <= '0';
            timeout_en_sync_d2  <= '0';
            timeout_en_sync_d3  <= '0';
            timeout_en_pulse    <= '0';
            ethernet_data       <= (others => '0');
            tx_enable           <= '0';

        elsif rising_edge(rgmii_clk) then
            -- 3-stage synchroniser + edge detect
            timeout_en_sync_d1 <= timeout_en;
            timeout_en_sync_d2 <= timeout_en_sync_d1;
            timeout_en_sync_d3 <= timeout_en_sync_d2;
            timeout_en_pulse   <= timeout_en_sync_d2 and not timeout_en_sync_d3;

            -- FIFO read pipeline
            fifo_rdreq_d1 <= fifo_rdreq;
            fifo_rdreq_d2 <= fifo_rdreq_d1;

            if timeout_en_pulse = '1' then
                fifo_rdreq <= '1';
            elsif unsigned(fifo_rdusedw) = 2 then
                fifo_rdreq <= '0';
            end if;

            if fifo_rdreq_d1 = '1' then
                ethernet_data <= fifo_q;
            else
                ethernet_data <= (others => '0');
            end if;

            tx_enable <= fifo_rdreq_d1;
        end if;
    end process read_control;

    ----------------------------------------------------------------------------
    -- DDIO output mapping
    --
    -- Per RGMII, the low nibble (bits 3:0) is presented on the rising edge
    -- of the TX clock and the high nibble (bits 7:4) on the falling edge.
    -- The Quartus altddio_out IP labels these datain_h / datain_l, so we
    -- swap them here.
    ----------------------------------------------------------------------------
    ddrio_in_h <= ethernet_data(3 downto 0);
    ddrio_in_l <= ethernet_data(7 downto 4);

    u_rgmii_io : entity work.rgmii_ddrio
        port map (
            aclr     => rst,
            datain_h => ddrio_in_l,
            datain_l => ddrio_in_h,
            outclock => rgmii_clk,
            dataout  => rgmii_txd
        );

    tx_ctl_ddrio_inst : entity work.tx_ctl_ddrio
        port map (
            aclr        => rst,
            datain_h(0) => tx_enable,
            datain_l(0) => tx_enable,
            outclock    => rgmii_clk,
            dataout(0)  => rgmii_tx_ctl
        );

    rgmii_txc <= rgmii_clk;

end architecture rtl;
