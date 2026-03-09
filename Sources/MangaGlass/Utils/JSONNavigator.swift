import Foundation

enum JSONError: Error {
    case invalidJSON
}

enum JSONNavigator {
    static func object(data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JSONError.invalidJSON
        }
        return object
    }

    static func string(_ any: Any?, keys: [String]) -> String? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func number(_ any: Any?, keys: [String]) -> Double? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
            if let value = dict[key] as? String, let number = Double(value) {
                return number
            }
        }
        return nil
    }

    static func array(_ any: Any?, keys: [String]) -> [Any]? {
        guard let dict = any as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? [Any] {
                return value
            }
        }
        return nil
    }
}
