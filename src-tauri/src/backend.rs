use crate::backend_api::*;

pub fn handle_event(a: &str) {
    unsafe {
        backendHandleEvent(a, 10);
    }
}
