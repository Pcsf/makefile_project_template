library lib_b;
use lib_b.doubled_pkg.all;

entity tb_named_libraries is
end entity tb_named_libraries;

architecture sim of tb_named_libraries is
begin
  test : process
  begin
    assert C_DOUBLED_VALUE = 42
      report "Named-library dependency resolution failed"
      severity failure;
    report "NAMED VHDL LIBRARIES TEST PASSED" severity note;
    wait;
  end process test;
end architecture sim;
