use hyper::http::Method;

pub const WIRE_VERSION: u8 = 1;
pub const STREAM_WIRE_VERSION: u8 = 1;
pub const STREAM_MSG_HEAD: u8 = 1;
pub const STREAM_MSG_CHUNK: u8 = 2;
pub const STREAM_MSG_END: u8 = 3;

#[derive(Debug)]
pub struct WireResponse {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

#[derive(Debug)]
pub enum StreamMsg {
    Head {
        status: u16,
        headers: Vec<(String, String)>,
        is_stream: bool,
        body: Vec<u8>,
    },
    Chunk(Vec<u8>),
    End,
}

fn method_to_u8(method: &Method) -> Result<u8, String> {
    match *method {
        Method::GET => Ok(0),
        Method::POST => Ok(1),
        Method::PUT => Ok(2),
        Method::PATCH => Ok(3),
        Method::DELETE => Ok(4),
        Method::OPTIONS => Ok(5),
        Method::HEAD => Ok(6),
        _ => Err(format!("unsupported method {}", method)),
    }
}

fn write_u8(buf: &mut Vec<u8>, v: u8) {
    buf.push(v);
}

#[allow(dead_code)]
fn write_u16(buf: &mut Vec<u8>, v: u16) {
    buf.extend_from_slice(&v.to_be_bytes());
}

fn write_u32(buf: &mut Vec<u8>, v: u32) {
    buf.extend_from_slice(&v.to_be_bytes());
}

fn write_bytes(buf: &mut Vec<u8>, bytes: &[u8]) -> Result<(), String> {
    let len = bytes.len();
    if len > u32::MAX as usize {
        return Err("value too large".to_string());
    }
    write_u32(buf, len as u32);
    buf.extend_from_slice(bytes);
    Ok(())
}

fn write_string(buf: &mut Vec<u8>, s: &str) -> Result<(), String> {
    write_bytes(buf, s.as_bytes())
}

fn write_opt_string(buf: &mut Vec<u8>, s: Option<&str>) -> Result<(), String> {
    match s {
        None => {
            write_u8(buf, 0);
            Ok(())
        }
        Some(v) => {
            write_u8(buf, 1);
            write_string(buf, v)
        }
    }
}

pub fn encode_request(
    method: &Method,
    path: &str,
    query: &str,
    headers: &[(String, String)],
    body: &[u8],
    remote: Option<&str>,
) -> Result<Vec<u8>, String> {
    let mut buf = Vec::new();
    write_u8(&mut buf, WIRE_VERSION);
    write_u8(&mut buf, method_to_u8(method)?);
    write_string(&mut buf, path)?;
    write_string(&mut buf, query)?;
    if headers.len() > u32::MAX as usize {
        return Err("too many headers".to_string());
    }
    write_u32(&mut buf, headers.len() as u32);
    for (k, v) in headers {
        write_string(&mut buf, k)?;
        write_string(&mut buf, v)?;
    }
    write_bytes(&mut buf, body)?;
    write_opt_string(&mut buf, remote)?;
    Ok(buf)
}

struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    fn read_u8(&mut self) -> Result<u8, String> {
        if self.pos >= self.data.len() {
            return Err("unexpected eof".to_string());
        }
        let b = self.data[self.pos];
        self.pos += 1;
        Ok(b)
    }

    fn read_u16(&mut self) -> Result<u16, String> {
        let b1 = self.read_u8()?;
        let b2 = self.read_u8()?;
        Ok(u16::from_be_bytes([b1, b2]))
    }

    fn read_u32(&mut self) -> Result<u32, String> {
        let b1 = self.read_u8()?;
        let b2 = self.read_u8()?;
        let b3 = self.read_u8()?;
        let b4 = self.read_u8()?;
        Ok(u32::from_be_bytes([b1, b2, b3, b4]))
    }

    fn read_bytes(&mut self) -> Result<Vec<u8>, String> {
        let len = self.read_u32()? as usize;
        if self.pos + len > self.data.len() {
            return Err("unexpected eof".to_string());
        }
        let out = self.data[self.pos..self.pos + len].to_vec();
        self.pos += len;
        Ok(out)
    }

    fn read_string(&mut self) -> Result<String, String> {
        let bytes = self.read_bytes()?;
        String::from_utf8(bytes).map_err(|_| "invalid utf-8".to_string())
    }
}

pub fn decode_response(bytes: &[u8]) -> Result<WireResponse, String> {
    let mut r = Reader::new(bytes);
    let ver = r.read_u8()?;
    if ver != WIRE_VERSION {
        return Err(format!("unsupported wire version {ver}"));
    }
    let status = r.read_u16()?;
    let header_count = r.read_u32()? as usize;
    let mut headers = Vec::with_capacity(header_count);
    for _ in 0..header_count {
        let k = r.read_string()?;
        let v = r.read_string()?;
        headers.push((k, v));
    }
    let body = r.read_bytes()?;
    Ok(WireResponse {
        status,
        headers,
        body,
    })
}

pub fn decode_stream_msg(bytes: &[u8]) -> Result<StreamMsg, String> {
    let mut r = Reader::new(bytes);
    let ver = r.read_u8()?;
    if ver != STREAM_WIRE_VERSION {
        return Err(format!("unsupported stream wire version {ver}"));
    }
    let kind = r.read_u8()?;
    match kind {
        STREAM_MSG_HEAD => {
            let status = r.read_u16()?;
            let is_stream = r.read_u8()? != 0;
            let header_count = r.read_u32()? as usize;
            let mut headers = Vec::with_capacity(header_count);
            for _ in 0..header_count {
                let k = r.read_string()?;
                let v = r.read_string()?;
                headers.push((k, v));
            }
            let body = r.read_bytes()?;
            Ok(StreamMsg::Head {
                status,
                headers,
                is_stream,
                body,
            })
        }
        STREAM_MSG_CHUNK => {
            let body = r.read_bytes()?;
            Ok(StreamMsg::Chunk(body))
        }
        STREAM_MSG_END => Ok(StreamMsg::End),
        _ => Err(format!("unknown stream message type {kind}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_response_roundtrip() {
        let mut buf = Vec::new();
        write_u8(&mut buf, WIRE_VERSION);
        write_u16(&mut buf, 201);
        write_u32(&mut buf, 1);
        write_string(&mut buf, "x-test").unwrap();
        write_string(&mut buf, "true").unwrap();
        write_bytes(&mut buf, b"ok").unwrap();

        let resp = decode_response(&buf).expect("decode response");
        assert_eq!(resp.status, 201);
        assert_eq!(resp.headers, vec![("x-test".to_string(), "true".to_string())]);
        assert_eq!(resp.body, b"ok");
    }

    #[test]
    fn decode_stream_messages() {
        let mut head = Vec::new();
        write_u8(&mut head, STREAM_WIRE_VERSION);
        write_u8(&mut head, STREAM_MSG_HEAD);
        write_u16(&mut head, 200);
        write_u8(&mut head, 1);
        write_u32(&mut head, 1);
        write_string(&mut head, "x-stream").unwrap();
        write_string(&mut head, "yes").unwrap();
        write_bytes(&mut head, b"head").unwrap();

        let msg = decode_stream_msg(&head).expect("decode head");
        match msg {
            StreamMsg::Head {
                status,
                headers,
                is_stream,
                body,
            } => {
                assert_eq!(status, 200);
                assert_eq!(headers, vec![("x-stream".to_string(), "yes".to_string())]);
                assert!(is_stream);
                assert_eq!(body, b"head");
            }
            _ => panic!("expected head"),
        }

        let mut chunk = Vec::new();
        write_u8(&mut chunk, STREAM_WIRE_VERSION);
        write_u8(&mut chunk, STREAM_MSG_CHUNK);
        write_bytes(&mut chunk, b"chunk").unwrap();
        let msg = decode_stream_msg(&chunk).expect("decode chunk");
        match msg {
            StreamMsg::Chunk(body) => assert_eq!(body, b"chunk"),
            _ => panic!("expected chunk"),
        }

        let mut end = Vec::new();
        write_u8(&mut end, STREAM_WIRE_VERSION);
        write_u8(&mut end, STREAM_MSG_END);
        let msg = decode_stream_msg(&end).expect("decode end");
        matches!(msg, StreamMsg::End);
    }

    #[test]
    fn decode_stream_msg_fuzzish() {
        let mut seed = 1u32;
        for len in 0..128usize {
            let mut data = vec![0u8; len];
            for b in data.iter_mut() {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                *b = (seed >> 24) as u8;
            }
            let _ = decode_stream_msg(&data);
        }
    }
}
