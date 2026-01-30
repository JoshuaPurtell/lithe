#include <lean/lean.h>
#include <string.h>

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

LEAN_EXPORT size_t lithe_byte_array_size(lean_object* o) {
    if (lean_is_sarray(o)) {
        return lean_sarray_size(o);
    }
    if (lean_is_ctor(o)) {
        lean_object* data = lean_ctor_get(o, 0);
        if (lean_is_array(data)) {
            return lean_array_size(data);
        }
    }
    return 0;
}

LEAN_EXPORT void lithe_byte_array_copy(lean_object* o, uint8_t* dst) {
    if (!dst) {
        return;
    }
    if (lean_is_sarray(o)) {
        size_t size = lean_sarray_size(o);
        if (size == 0) return;
        memcpy(dst, lean_sarray_cptr(o), size);
        return;
    }
    if (lean_is_ctor(o)) {
        lean_object* data = lean_ctor_get(o, 0);
        if (!lean_is_array(data)) return;
        size_t size = lean_array_size(data);
        for (size_t i = 0; i < size; i++) {
            lean_object* elem = lean_array_get_core(data, i);
            dst[i] = (uint8_t)lean_unbox(elem);
        }
    }
}
