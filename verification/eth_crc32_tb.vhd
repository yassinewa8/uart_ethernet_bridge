--------------------------------------------------------------------------------
-- eth_crc32_tb
--
-- Drives a couple of byte sequences into eth_crc32 with data_valid held high
-- continuously, then drops data_valid and reports the resulting CRC. The
-- expected values can be checked against Python's binascii.crc32, e.g.:
--
--   >>> import binascii
--   >>> binascii.crc32(bytes([0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09]))
--   0x40EFAB9E
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_crc32_tb is
end entity eth_crc32_tb;

architecture sim of eth_crc32_tb is

    signal clk        : std_logic                    := '0';
    signal rst        : std_logic                    := '1';
    signal data_in    : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid : std_logic                    := '0';
    signal crc_out    : std_logic_vector(31 downto 0);
    signal crc_valid  : std_logic;

    constant CLK_PERIOD : time := 10 ns;

    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

    constant TEST_PACKET_1 : byte_array_t := (
        x"01", x"02", x"03", x"04", x"05",
        x"06", x"07", x"08", x"09"
    );

    constant TEST_PACKET_2 : byte_array_t := (
        x"AA", x"AA", x"BB", x"BB", x"CC",
        x"CC", x"DD", x"EE", x"FF"
    );

begin

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : entity work.eth_crc32
        port map (
            clk        => clk,
            rst        => rst,
            data_in    => data_in,
            data_valid => data_valid,
            crc_out    => crc_out,
            crc_valid  => crc_valid
        );

    clk <= not clk after CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim : process

        procedure send_packet (constant pkt : in byte_array_t) is
        begin
            for i in pkt'range loop
                data_in    <= pkt(i);
                data_valid <= '1';
                wait until rising_edge(clk);
            end loop;
            -- Falling edge of data_valid triggers CRC finalize next cycle
            data_valid <= '0';
            data_in    <= (others => '0');
        end procedure send_packet;

    begin
        ------------------------------------------------------------------------
        -- Packet 1
        ------------------------------------------------------------------------
        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        send_packet(TEST_PACKET_1);
        wait until rising_edge(clk) and crc_valid = '1';
        report "CRC-32 result = 0x" & to_hstring(crc_out) severity note;

        ------------------------------------------------------------------------
        -- Packet 2 (with reset between)
        ------------------------------------------------------------------------
        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);
        wait for 5 * CLK_PERIOD;

        send_packet(TEST_PACKET_2);
        wait until rising_edge(clk) and crc_valid = '1';
        report "CRC-32 result = 0x" & to_hstring(crc_out) severity note;

        wait for 5 * CLK_PERIOD;
        wait;
    end process stim;

end architecture sim;
