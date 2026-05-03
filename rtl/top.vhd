--------------------------------------------------------------------------------
-- top
--
-- Top-level design for the UART <-> RGMII bridge on the Cyclone 10 LP
-- evaluation kit. Brings up the PLL, instantiates the UART and RGMII RX
-- blocks, and routes RGMII RX bytes through a dual-clock FIFO out to the
-- UART TX (loopback / capture path).
--
-- Auxiliary features:
--   * blinks the on-board LED at 1 Hz as a "device is programmed" indicator
--   * toggles uart_led_xor on receipt of ASCII '2' / '3' as a UART sanity
--     check
--
-- Reset polarity:
--   The board's reset button is active-low, so rst is inverted to produce
--   the internal active-high 'reset' used by every submodule.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
    port (
        -- Clock and reset
        clk          : in  std_logic;
        rst          : in  std_logic;  -- board button (active low)

        -- UART
        uart_rx_pin  : in  std_logic;
        uart_tx_pin  : out std_logic;

        -- LEDs
        led          : out std_logic;
        uart_led_xor : out std_logic;

        -- RGMII
        rgmii_rxd    : in  std_logic_vector(3 downto 0);
        rgmii_rx_ctl : in  std_logic;
        rgmii_rxc    : in  std_logic;

        rgmii_txd    : out std_logic_vector(3 downto 0);
        rgmii_tx_ctl : out std_logic;
        rgmii_txc    : out std_logic
    );
end entity top;

architecture rtl of top is

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------
    constant CLK_FREQ    : integer := 100_000_000;    -- 100 MHz internal clock
    constant BLINK_FREQ  : integer := 1;              -- 1 Hz blink
    constant UART_BAUD   : integer := 921_600;        -- UART baud rate
    constant COUNT_LIMIT : integer := CLK_FREQ / (2 * BLINK_FREQ);

    constant ASCII_2 : std_logic_vector(7 downto 0) := "00110010";  -- '2'
    constant ASCII_3 : std_logic_vector(7 downto 0) := "00110011";  -- '3'

    ----------------------------------------------------------------------------
    -- Clocks and reset
    ----------------------------------------------------------------------------
    signal clk_100mhz : std_logic;
    signal clk_125mhz : std_logic;
    signal reset      : std_logic;

    ----------------------------------------------------------------------------
    -- LED / blink
    ----------------------------------------------------------------------------
    signal counter : unsigned(26 downto 0) := (others => '0');
    signal led_reg : std_logic             := '0';

    ----------------------------------------------------------------------------
    -- UART
    ----------------------------------------------------------------------------
    signal uart_rx_sync        : std_logic_vector(1 downto 0) := (others => '0');
    signal uart_rx_data        : std_logic_vector(7 downto 0) := (others => '0');
    signal uart_rx_data_latched: std_logic_vector(7 downto 0) := (others => '0');
    signal uart_rx_valid       : std_logic                    := '0';
    signal uart_valid_sr       : std_logic_vector(3 downto 0) := (others => '0');

    ----------------------------------------------------------------------------
    -- RGMII RX byte stream
    ----------------------------------------------------------------------------
    signal rx_data_clk   : std_logic;
    signal rx_data       : std_logic_vector(7 downto 0);
    signal rx_data_valid : std_logic;
    signal rx_data_err   : std_logic;

    ----------------------------------------------------------------------------
    -- Cross-domain FIFO and drain control
    ----------------------------------------------------------------------------
    signal sync_fifo_q       : std_logic_vector(7 downto 0);
    signal sync_fifo_rden    : std_logic;
    signal sync_fifo_rden_sr : std_logic_vector(7 downto 0);
    signal sync_fifo_rdusedw : std_logic_vector(8 downto 0);
    signal read_counter      : unsigned(16 downto 0);

begin

    ----------------------------------------------------------------------------
    -- Concurrent assignments
    ----------------------------------------------------------------------------
    reset <= not rst;       -- board button is active-low; flip to active-high
    led   <= led_reg;

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------
    clk_pll : entity work.pll_test
        port map (
            areset => reset,
            inclk0 => clk,
            c0     => clk_100mhz,
            c1     => clk_125mhz
        );

    ----------------------------------------------------------------------------
    -- UART receiver
    ----------------------------------------------------------------------------
    uart_rx_inst : entity work.uart_rx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => UART_BAUD
        )
        port map (
            clk           => clk_100mhz,
            rst           => reset,
            uart_rx       => uart_rx_sync(1),
            uart_rx_data  => uart_rx_data,
            uart_rx_valid => uart_rx_valid,
            uart_rx_err   => open
        );

    ----------------------------------------------------------------------------
    -- UART transmitter
    ----------------------------------------------------------------------------
    uart_tx_inst : entity work.uart_tx
        generic map (
            CLK_FREQ  => CLK_FREQ,
            BAUD_RATE => UART_BAUD
        )
        port map (
            clk           => clk_100mhz,
            rst           => reset,
            uart_tx_data  => sync_fifo_q,
            uart_tx_start => sync_fifo_rden_sr(7),
            uart_tx       => uart_tx_pin,
            uart_tx_busy  => open
        );

    ----------------------------------------------------------------------------
    -- RGMII receiver
    ----------------------------------------------------------------------------
    rgmii_rx_inst : entity work.rgmii_rx
        port map (
            rst           => reset,
            rgmii_rxc     => rgmii_rxc,
            rgmii_rxd     => rgmii_rxd,
            rgmii_rx_ctl  => rgmii_rx_ctl,
            rx_data_clk   => rx_data_clk,
            rx_data       => rx_data,
            rx_data_valid => rx_data_valid,
            rx_data_err   => open
        );

    ----------------------------------------------------------------------------
    -- Cross-domain FIFO (RGMII RX clock -> 100 MHz UART clock)
    ----------------------------------------------------------------------------
    uart_sync_fifo_inst : entity work.uart_sync_fifo
        port map (
            wrclk   => rx_data_clk,
            data    => rx_data,
            wrreq   => rx_data_valid,
            rdclk   => clk_100mhz,
            rdreq   => sync_fifo_rden,
            q       => sync_fifo_q,
            rdusedw => sync_fifo_rdusedw,
            wrempty => open,
            wrfull  => open
        );

    ----------------------------------------------------------------------------
    -- UART -> RGMII bridge (currently disabled)
    ----------------------------------------------------------------------------
    -- uart_to_rgmii_bridge_inst : entity work.uart_to_rgmii_bridge
    --     port map (
    --         rst          => reset,
    --         uart_clk     => clk_100mhz,
    --         uart_data    => uart_rx_data,
    --         uart_valid   => uart_rx_valid,
    --         rgmii_clk    => clk_125mhz,
    --         rgmii_txd    => rgmii_txd,
    --         rgmii_tx_ctl => rgmii_tx_ctl,
    --         rgmii_txc    => rgmii_txc
    --     );

    ----------------------------------------------------------------------------
    -- sync_uart_rx
    --
    -- 2-FF synchroniser on the asynchronous UART RX line.
    ----------------------------------------------------------------------------
    sync_uart_rx : process (clk_100mhz, reset)
    begin
        if reset = '1' then
            uart_rx_sync <= (others => '0');
        elsif rising_edge(clk_100mhz) then
            uart_rx_sync <= uart_rx_sync(0) & uart_rx_pin;
        end if;
    end process sync_uart_rx;

    ----------------------------------------------------------------------------
    -- blink_led
    --
    -- 1 Hz toggle on the on-board LED. Visual sign that the bitstream is
    -- programmed and the design is being clocked.
    ----------------------------------------------------------------------------
    blink_led : process (clk_100mhz, reset)
    begin
        if reset = '1' then
            counter <= (others => '0');
            led_reg <= '0';
        elsif rising_edge(clk_100mhz) then
            if counter = COUNT_LIMIT - 1 then
                counter <= (others => '0');
                led_reg <= not led_reg;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process blink_led;

    ----------------------------------------------------------------------------
    -- led_control
    --
    -- ASCII '2' on UART sets uart_led_xor; ASCII '3' clears it. Used as a
    -- quick UART RX sanity check on the second LED.
    ----------------------------------------------------------------------------
    led_control : process (clk_100mhz, reset)
    begin
        if reset = '1' then
            uart_rx_data_latched <= (others => '0');
            uart_led_xor         <= '0';
            uart_valid_sr        <= (others => '0');
        elsif rising_edge(clk_100mhz) then
            uart_valid_sr <= uart_valid_sr(2 downto 0) & uart_rx_valid;

            if uart_rx_valid = '1' then
                uart_rx_data_latched <= uart_rx_data;
            end if;

            if uart_rx_data_latched = ASCII_2 then
                uart_led_xor <= '1';
            elsif uart_rx_data_latched = ASCII_3 then
                uart_led_xor <= '0';
            end if;
        end if;
    end process led_control;

    ----------------------------------------------------------------------------
    -- fifo_drain_control
    --
    -- Periodically pulses sync_fifo_rden when there is at least one word in
    -- the cross-domain FIFO. The 8-bit shift register sync_fifo_rden_sr
    -- delays the read enable so that the byte read out of the FIFO has time
    -- to settle before being handed to the UART TX as 'start'.
    ----------------------------------------------------------------------------
    fifo_drain_control : process (clk_100mhz, reset)
    begin
        if reset = '1' then
            sync_fifo_rden    <= '0';
            sync_fifo_rden_sr <= (others => '0');
            read_counter      <= (others => '0');
        elsif rising_edge(clk_100mhz) then
            sync_fifo_rden_sr <= sync_fifo_rden_sr(6 downto 0) & sync_fifo_rden;

            if read_counter = 10_000 then
                read_counter <= (others => '0');
                if unsigned(sync_fifo_rdusedw) > 0 then
                    sync_fifo_rden <= '1';
                end if;
            else
                sync_fifo_rden <= '0';
                read_counter   <= read_counter + 1;
            end if;
        end if;
    end process fifo_drain_control;

end architecture rtl;
