#include <experimental/meta> // P2996 reflection library (std::meta)
#include <print>
#include <string>
#include <type_traits>

// Map any enum value to its name at compile time via reflection.
template <typename E>
  requires std::is_enum_v<E>
constexpr std::string enum_to_string(E value) {
  std::string result = "<unnamed>";

  // ^^E            : reflect the enum type        -> std::meta::info
  // enumerators_of : list its enumerators         -> vector<info>
  // template for   : expansion statement, one iteration per enumerator
  template for (constexpr auto e :
                std::define_static_array(std::meta::enumerators_of(^^E))) {
    if (value == [:e:]) { // [:e:] splices the enumerator back into code
      result = std::string(std::meta::identifier_of(e));
    }
  }
  return result;
}

enum class Color { red, green, blue };

int main() {
  // Works in constant expressions...
  static_assert(enum_to_string(Color::green) == "green");

  // ...and at runtime.
  std::println("{}", enum_to_string(Color::blue)); // blue
  std::println("{}", enum_to_string(Color(42)));   // <unnamed>
}
