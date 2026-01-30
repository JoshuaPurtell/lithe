#include <lean/lean.h>

LEAN_EXPORT lean_object* lithe_lean_alloc_sarray(uint32_t elem_size, size_t size, size_t capacity) {
    return lean_alloc_sarray(elem_size, size, capacity);
}

LEAN_EXPORT uint8_t* lithe_lean_sarray_cptr(lean_object* o) {
    return lean_sarray_cptr(o);
}

LEAN_EXPORT size_t lithe_lean_sarray_size(lean_object* o) {
    return lean_sarray_size(o);
}

LEAN_EXPORT bool lithe_lean_io_result_is_ok(lean_object* r) {
    return lean_io_result_is_ok(r);
}

LEAN_EXPORT lean_object* lithe_lean_io_result_get_value(lean_object* r) {
    return lean_io_result_get_value(r);
}

LEAN_EXPORT lean_object* lithe_lean_io_result_get_error(lean_object* r) {
    return lean_io_result_get_error(r);
}

LEAN_EXPORT uint64_t lithe_lean_unbox_uint64(lean_object* o) {
    return lean_unbox_uint64(o);
}

LEAN_EXPORT void lithe_lean_dec(lean_object* o) {
    lean_dec(o);
}
