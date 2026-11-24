//! Supervisor and Zeus-facing socket for a local Haru conversation.
//!
//! The model is a child process (`python -m haru_mlx.native`). This crate does
//! not download weights and does not open a TCP connection. Tests use
//! [`backend::FakeBackend`] and synthetic frames only.

pub mod backend;
pub mod cli;
pub mod engine;
pub mod protocol;
pub mod serve;
pub mod session;
pub mod supervisor;
pub mod upstream;
pub mod watchdog;

pub use cli::run;
pub use engine::{selftest_report, SelftestReport};
pub use session::{SessionError, SessionEvent, SessionState, FRAME_SAMPLES};
