--------------------------------------------------------------------------------
-- rgmii_rx
--
-- RGMII receive front-end. Captures the DDR rxd nibbles and rx_ctl on a
-- phase-shifted copy of rgmii_rxc, reassembles 8-bit bytes (low nibble on
-- rising edge, high nibble on falling edge per the RGMII spec) and exposes a
-- byte-wide synchronous-style interface to the rest of the design.
--
-- Notes:
--   * The phase shift is provided by the rgmii_rx_clk PLL (Quartus IP). Its
--     locked output gates internal resets so the data path stays held in
--     reset until the shifted clock is stable.
--   * rgmii_rxc / rgmii_rxd / rgmii_rx_ctl are RGMII PHY-side names and kept
--     verbatim from the spec.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rgmii_rx is
    port (
        -- Global reset (active high)
        rst           : in  std_logic;

        -- RGMII PHY interface
        rgmii_rxc     : in  std_logic;
        rgmii_rxd     : in  std_logic_vector(3 downto 0);
        rgmii_rx_ctl  : in  std_logic;

        -- Internal byte-wide interface
        rx_data_clk   : out std_logic;
        rx_data       : out std_logic_vector(7 downto 0);
        rx_data_valid : out std_logic;
        rx_data_err   : out std_logic
    );
end entity rgmii_rx;

architecture rtl of rgmii_rx is

    -- Phase-shifted RX clock and PLL lock
    signal rgmii_rxc_shifted : std_logic;
    signal pll_locked        : std_logic;
    signal combined_rst      : std_logic;

    -- Raw DDR captures
    signal raw_data_h : std_logic_vector(3 downto 0);
    signal raw_data_l : std_logic_vector(3 downto 0);
    signal raw_ctl_h  : std_logic;
    signal raw_ctl_l  : std_logic;

    -- Pipeline stage 1
    signal data_h_d1 : std_logic_vector(3 downto 0);
    signal data_l_d1 : std_logic_vector(3 downto 0);
    signal ctl_h_d1  : std_logic;
    signal ctl_l_d1  : std_logic;

    -- Pipeline stage 2
    signal data_h_d2 : std_logic_vector(3 downto 0);
    signal data_l_d2 : std_logic_vector(3 downto 0);
    signal ctl_h_d2  : std_logic;
    signal ctl_l_d2  : std_logic;

begin

    ----------------------------------------------------------------------------
    -- Clocking and reset
    ----------------------------------------------------------------------------
    rx_data_clk  <= rgmii_rxc_shifted;
    combined_rst <= rst or (not pll_locked);

    phase_shift_pll : entity work.rgmii_rx_clk
        port map (
            areset => rst,
            inclk0 => rgmii_rxc,
            c0     => rgmii_rxc_shifted,
            locked => pll_locked
        );

    ----------------------------------------------------------------------------
    -- DDR data capture
    ----------------------------------------------------------------------------
    ddr_rxd_inst : entity work.ddr_rxd
        port map (
            aclr      => combined_rst,
            datain    => rgmii_rxd,
            inclock   => rgmii_rxc_shifted,
            dataout_h => raw_data_h,  -- rising edge
            dataout_l => raw_data_l   -- falling edge
        );

    ----------------------------------------------------------------------------
    -- DDR control capture
    ----------------------------------------------------------------------------
    ddr_ctl_inst : entity work.ddr_ctl
        port map (
            aclr         => combined_rst,
            datain(0)    => rgmii_rx_ctl,
            inclock      => rgmii_rxc_shifted,
            dataout_h(0) => raw_ctl_h,  -- RX_DV
            dataout_l(0) => raw_ctl_l   -- RX_DV xor RX_ER
        );

    ----------------------------------------------------------------------------
    -- align_and_assemble
    --
    -- Two pipeline stages keep the H/L pair aligned, then the byte is
    -- reassembled (rising-edge nibble on the high side per RGMII).
    ----------------------------------------------------------------------------
    align_and_assemble : process (rgmii_rxc_shifted)
    begin
        if rising_edge(rgmii_rxc_shifted) then

            -- Stage 1
            data_h_d1 <= raw_data_h;
            data_l_d1 <= raw_data_l;
            ctl_h_d1  <= raw_ctl_h;
            ctl_l_d1  <= raw_ctl_l;

            -- Stage 2
            data_h_d2 <= data_h_d1;
            data_l_d2 <= data_l_d1;
            ctl_h_d2  <= ctl_h_d1;
            ctl_l_d2  <= ctl_l_d1;

            -- Byte reassembly + control
            rx_data       <= data_h_d2 & data_l_d2;
            rx_data_valid <= ctl_h_d2;
            rx_data_err   <= ctl_h_d2 xor ctl_l_d2;

        end if;
    end process align_and_assemble;

end architecture rtl;
