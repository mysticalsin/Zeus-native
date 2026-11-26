/// Lowest layer of the shared earbuds types.
/// `BluetoothAccess` is the class-property grant: not asked, restricted,
/// denied, or allowed. The four codes are the header order. A code outside
/// those four is not an access value. Classic calls are allowed only for
/// `.allowed`, and a prompt is asked only while the value is still not asked.
/// This file keeps no device name. Every other earbuds type stays out.
public enum BluetoothAccess: Int, Sendable, Equatable, Hashable, CaseIterable {
    case notAsked = 0
    case restricted = 1
    case denied = 2
    case allowed = 3

    /// Maps one class-property code. Any other integer is not an access value.
    public static func read(_ code: Int) -> BluetoothAccess? {
        BluetoothAccess(rawValue: code)
    }

    /// Classic Bluetooth calls are allowed only for this value.
    public var allowsClassicCalls: Bool {
        self == .allowed
    }

    /// A prompt is asked only while the class property is still not asked.
    public var mayAsk: Bool {
        self == .notAsked
    }
}
