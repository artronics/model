#[link(name = "backend", kind = "static")]
extern "C" {
    pub fn add(a: usize, b: usize) -> usize;
    pub fn backendHandleEvent(a: &str, len: usize);
}


