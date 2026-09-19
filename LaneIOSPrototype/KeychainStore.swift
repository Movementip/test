import Foundation
import Security

enum KeychainStore {
    private static let service = "LaneIOSPrototype"
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        SecItemDelete(q as CFDictionary)
        var add=q; add[kSecValueData as String]=data
        SecItemAdd(add as CFDictionary,nil)
    }
    static func load(account: String) -> String? {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var item: CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess, let d=item as? Data else{return nil}
        return String(data:d,encoding:.utf8)
    }
    static func delete(account:String){
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
        SecItemDelete(q as CFDictionary)
    }
}