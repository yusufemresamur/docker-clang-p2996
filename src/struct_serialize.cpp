#include <array>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <experimental/meta> // P2996 reflection library (std::meta)
#include <print>
#include <span>

// Types whose value is fully contained in their bytes - safe to memcpy.
// Rejects anything with heap-owned data (std::vector, std::string, ...).
template <typename T>
concept Serializable = std::is_trivially_copyable_v<T>;

// Sum sizeof of each field — excludes inter-field padding unlike sizeof(T).
//
//  ^^T                          reflect operator -> std::meta::info for T
//  nonstatic_data_members_of    list all fields  -> consteval vector<info>
//  access_context::unchecked()  skip visibility checks (include private fields)
//  define_static_array          materialize the consteval range so template for can iterate it
//  template for                 expansion statement: one instantiation per element
//  std::meta::size_of(m)        sizeof the field's type via reflection (no object needed)
template <typename T> consteval size_t packed_size() {
  size_t n = 0;
  template for (constexpr auto m :
                std::define_static_array(std::meta::nonstatic_data_members_of(
                    ^^T, std::meta::access_context::unchecked()))) {
    n += std::meta::size_of(m);
  }
  return n;
}

// Serialize each field in declaration order, no padding bytes.
template <Serializable T>
std::array<uint8_t, packed_size<T>()> serialize(const T &obj) {
  std::array<uint8_t, packed_size<T>()> buf{};
  size_t offset = 0;

  template for (constexpr auto m :
                std::define_static_array(std::meta::nonstatic_data_members_of(
                    ^^T, std::meta::access_context::unchecked()))) {
    const auto &field = obj.[:m:]; // [:m:] splice: turns the reflection back
                                   // into a member access
    std::memcpy(buf.data() + offset, &field, sizeof(field));
    offset += sizeof(field);
  }
  return buf;
}

// Deserialize the same field order back into T.
template <Serializable T>
T deserialize(std::span<const uint8_t> buf) {
  assert(buf.size() == packed_size<T>() && "buffer size does not match packed size of T");
  T obj{};
  size_t offset = 0;

  template for (constexpr auto m :
                std::define_static_array(std::meta::nonstatic_data_members_of(
                    ^^T, std::meta::access_context::unchecked()))) {
    auto &field = obj.[:m:];
    std::memcpy(&field, buf.data() + offset, sizeof(field));
    offset += sizeof(field);
  }
  return obj;
}

// char(1) + padding(3) + int(4) + char(1) + padding(3) = sizeof 12, packed 6
struct Padded {
  char a;
  int b;
  char c;
};

// uniform alignment - no gaps, sizeof == packed_size
struct Flat {
  int x;
  int y;
  int z;
};

// templated struct - reflection and serialization work for any scalar type
template <typename Scalar> struct Point {
  Scalar x;
  Scalar y;
};

template <typename T> void print_fields(const T &obj) {
  std::print("{{ ");
  bool first = true;
  template for (constexpr auto m :
                std::define_static_array(std::meta::nonstatic_data_members_of(
                    ^^T, std::meta::access_context::unchecked()))) {
    if (!first) {
      std::print(", ");
    }
    std::print("{}: {}", std::meta::identifier_of(m),
               obj.[:m:]); // identifier_of -> field name as string_view
    first = false;
  }
  std::println(" }}");
}

template <typename T> void demo(const std::string_view label, const T &obj) {
  std::println("--- {} ---", label);
  std::println("sizeof={}, packed_size={}", sizeof(T), packed_size<T>());
  const auto bytes = serialize(obj);
  std::print("serialized ({}):", bytes.size());
  for (const uint8_t b : bytes) {
    std::print(" {:02x}", b);
  }
  std::println("");
  const T obj2 = deserialize<T>(bytes);
  std::print("deserialized: ");
  print_fields(obj2);
}

int main() {
  demo("Padded", Padded{'X', 42, 'Z'});
  demo("Flat", Flat{1, 2, 3});
  demo("Point<int>", Point<int>{10, 20});
  demo("Point<float>", Point<float>{1.5f, 2.5f});
  demo("Point<double>", Point<double>{3.14, 2.71});
}
