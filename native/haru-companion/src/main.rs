fn main() {
    let code = haru_companion::run(std::env::args().skip(1));
    std::process::exit(code);
}
