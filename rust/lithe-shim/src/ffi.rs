#[repr(C)]
pub struct lean_object {
    _private: [u8; 0],
}

extern "C" {
    pub fn lean_initialize_runtime_module();
    pub fn lean_initialize();
    pub fn lean_initialize_thread();
    pub fn lean_init_task_manager();
    pub fn lean_finalize_task_manager();

    pub fn lean_io_result_show_error(r: *mut lean_object);

    pub fn lithe_lean_io_result_is_ok(r: *mut lean_object) -> bool;
    pub fn lithe_lean_io_result_get_value(r: *mut lean_object) -> *mut lean_object;
    #[allow(dead_code)]
    pub fn lithe_lean_io_result_get_error(r: *mut lean_object) -> *mut lean_object;

    pub fn lithe_lean_unbox_uint64(o: *mut lean_object) -> u64;
    pub fn lithe_lean_alloc_sarray(elem_size: u32, size: usize, capacity: usize) -> *mut lean_object;
    pub fn lithe_lean_sarray_cptr(o: *mut lean_object) -> *mut u8;
    pub fn lithe_lean_sarray_size(o: *mut lean_object) -> usize;
    pub fn lithe_lean_dec(o: *mut lean_object);
    pub fn lithe_byte_array_size(o: *mut lean_object) -> usize;
    pub fn lithe_byte_array_copy(o: *mut lean_object, dst: *mut u8);

    #[cfg(lithe_example = "hello")]
    pub fn initialize_hello_Hello(builtin: u8) -> *mut lean_object;
    #[cfg(lithe_example = "crafter")]
    pub fn initialize_crafter_Crafter(builtin: u8) -> *mut lean_object;

    pub fn lithe_new_app_named(name: *mut lean_object) -> *mut lean_object;
    pub fn lithe_handle(app: u64, req: *mut lean_object) -> *mut lean_object;
    pub fn lithe_free_app(app: u64) -> *mut lean_object;
    pub fn lithe_handle_async(app: u64, req: *mut lean_object) -> *mut lean_object;
    pub fn lithe_poll_response(req_id: u64) -> *mut lean_object;
    pub fn lithe_cancel_request(req_id: u64) -> *mut lean_object;
    pub fn lithe_stream_start(app: u64, req: *mut lean_object) -> *mut lean_object;
    pub fn lithe_stream_push_body(
        req_id: u64,
        chunk: *mut lean_object,
        is_last: u64,
    ) -> *mut lean_object;
    pub fn lithe_stream_poll_response(req_id: u64) -> *mut lean_object;
    pub fn lithe_stream_cancel(req_id: u64) -> *mut lean_object;

    pub fn lithe_ws_push(ws_id: u64, msg: *mut lean_object) -> *mut lean_object;
    pub fn lithe_ws_poll(ws_id: u64) -> *mut lean_object;
    pub fn lithe_ws_close(ws_id: u64) -> *mut lean_object;

    #[allow(dead_code)]
    pub fn hello_new_app() -> *mut lean_object;
    #[allow(dead_code)]
    pub fn hello_handle(app: u64, req: *mut lean_object) -> *mut lean_object;
    #[allow(dead_code)]
    pub fn hello_free_app(app: u64) -> *mut lean_object;
}

pub unsafe fn mk_byte_array(data: &[u8]) -> *mut lean_object {
    let size = data.len();
    let arr = lithe_lean_alloc_sarray(1, size, size);
    let dst = lithe_lean_sarray_cptr(arr);
    std::ptr::copy_nonoverlapping(data.as_ptr(), dst, size);
    arr
}

pub unsafe fn byte_array_to_vec(arr: *mut lean_object) -> Vec<u8> {
    let size = lithe_byte_array_size(arr);
    if size == 0 {
        return Vec::new();
    }
    let mut out = vec![0u8; size];
    lithe_byte_array_copy(arr, out.as_mut_ptr());
    out
}

pub unsafe fn unwrap_io_result<T>(res: *mut lean_object, f: impl FnOnce(*mut lean_object) -> T) -> T {
    if lithe_lean_io_result_is_ok(res) {
        let val = lithe_lean_io_result_get_value(res);
        let out = f(val);
        lithe_lean_dec(res);
        out
    } else {
        lean_io_result_show_error(res);
        panic!("lean IO error");
    }
}
