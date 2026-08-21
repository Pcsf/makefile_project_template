library lib_a;
use lib_a.value_pkg.all;

package doubled_pkg is
  constant C_DOUBLED_VALUE : natural := 2 * C_VALUE;
end package doubled_pkg;
