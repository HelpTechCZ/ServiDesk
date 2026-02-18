import Foundation
import CryptoKit

/// End-to-end šifrování: ECDH P-256 key exchange + AES-256-GCM.
/// Relay server vidí pouze šifrovaná data (zero-knowledge).
class E2ECrypto {
    private static let hkdfSalt = "servidesk-e2e"
    private static let hkdfInfo = "aes-key"
    private static let nonceSize = 12
    private static let tagSize = 16

    private var privateKey: P256.KeyAgreement.PrivateKey?
    private var sharedKey: SymmetricKey?
    private var noncePrefix: Data?
    private var nonceCounter: UInt64 = 0
    private let counterLock = NSLock()

    /// True pokud byl úspěšně odvozen sdílený klíč a šifrování je připraveno.
    var isReady: Bool { sharedKey != nil }

    /// Vygeneruje ECDH P-256 key pair a vrátí veřejný klíč jako base64
    /// (65 bytů, uncompressed point: 0x04 + 32B X + 32B Y).
    func generateKeyPair() -> String {
        let key = P256.KeyAgreement.PrivateKey()
        privateKey = key

        // rawRepresentation = 65B uncompressed point (0x04 prefix included)
        let publicKeyData = key.publicKey.x963Representation

        // Připravit nonce prefix (4B random)
        var prefix = Data(count: 4)
        prefix.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 4, ptr.baseAddress!)
        }
        noncePrefix = prefix
        nonceCounter = 0

        return publicKeyData.base64EncodedString()
    }

    /// Odvodí sdílený AES-256 klíč z peer's public key přes ECDH + HKDF.
    func deriveSharedKey(peerPublicKeyBase64: String) throws {
        guard let privateKey = privateKey else {
            throw E2EError.keyPairNotGenerated
        }

        guard let peerKeyData = Data(base64Encoded: peerPublicKeyBase64) else {
            throw E2EError.invalidPeerKey
        }

        // Import peer's uncompressed public key
        let peerPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: peerKeyData)

        // ECDH shared secret
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)

        // HKDF: shared_secret → AES-256 key
        let salt = Data(Self.hkdfSalt.utf8)
        let info = Data(Self.hkdfInfo.utf8)
        sharedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    /// Šifruje data pomocí AES-256-GCM.
    /// Formát výstupu: [12B nonce][ciphertext][16B tag]
    func encrypt(_ plaintext: Data) throws -> Data {
        guard let key = sharedKey else {
            throw E2EError.keyNotDerived
        }

        let nonce = try AES.GCM.Nonce(data: generateNonce())
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        // Složit: [nonce][ciphertext][tag]
        var result = Data()
        result.append(contentsOf: sealedBox.nonce)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)
        return result
    }

    /// Dešifruje data z formátu [12B nonce][ciphertext][16B tag].
    func decrypt(_ encrypted: Data) throws -> Data {
        guard let key = sharedKey else {
            throw E2EError.keyNotDerived
        }

        guard encrypted.count >= Self.nonceSize + Self.tagSize else {
            throw E2EError.dataTooShort
        }

        let nonce = encrypted[0..<Self.nonceSize]
        let ciphertextEnd = encrypted.count - Self.tagSize
        let ciphertext = encrypted[Self.nonceSize..<ciphertextEnd]
        let tag = encrypted[ciphertextEnd...]

        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )

        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Šifruje string a vrátí base64 (pro JSON payload).
    func encryptToBase64(_ plaintext: String) throws -> String {
        let data = Data(plaintext.utf8)
        let encrypted = try encrypt(data)
        return encrypted.base64EncodedString()
    }

    /// Dešifruje base64 string zpět na plaintext string.
    func decryptFromBase64(_ encryptedBase64: String) throws -> String {
        guard let encrypted = Data(base64Encoded: encryptedBase64) else {
            throw E2EError.invalidBase64
        }
        let decrypted = try decrypt(encrypted)
        guard let text = String(data: decrypted, encoding: .utf8) else {
            throw E2EError.invalidUTF8
        }
        return text
    }

    /// Resetuje stav pro novou session.
    func reset() {
        privateKey = nil
        sharedKey = nil
        noncePrefix = nil
        nonceCounter = 0
    }

    /// Generuje unikátní nonce: [4B random prefix][8B counter].
    private func generateNonce() -> Data {
        counterLock.lock()
        nonceCounter += 1
        let counter = nonceCounter
        counterLock.unlock()

        var nonce = Data(count: Self.nonceSize)
        nonce[0..<4] = noncePrefix![0..<4]
        withUnsafeBytes(of: counter.littleEndian) { counterBytes in
            nonce[4..<12] = Data(counterBytes)
        }
        return nonce
    }
}

// MARK: - Errors

enum E2EError: LocalizedError {
    case keyPairNotGenerated
    case invalidPeerKey
    case keyNotDerived
    case dataTooShort
    case invalidBase64
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .keyPairNotGenerated: return "Key pair not generated. Call generateKeyPair() first."
        case .invalidPeerKey: return "Invalid peer public key format."
        case .keyNotDerived: return "Shared key not derived. Complete key exchange first."
        case .dataTooShort: return "Encrypted data too short."
        case .invalidBase64: return "Invalid base64 encoded data."
        case .invalidUTF8: return "Decrypted data is not valid UTF-8."
        }
    }
}
