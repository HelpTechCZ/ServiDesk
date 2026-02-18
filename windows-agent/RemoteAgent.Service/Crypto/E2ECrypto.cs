using System.Security.Cryptography;

namespace RemoteAgent.Service.Crypto;

/// <summary>
/// End-to-end šifrování: ECDH P-256 key exchange + AES-256-GCM.
/// Relay server vidí pouze šifrovaná data (zero-knowledge).
/// </summary>
public class E2ECrypto : IDisposable
{
    private const int NonceSize = 12;  // AES-GCM standard
    private const int TagSize = 16;    // AES-GCM tag
    private const string HkdfSalt = "servidesk-e2e";
    private const string HkdfInfo = "aes-key";

    private ECDiffieHellman? _ecdh;
    private byte[]? _sharedKey;
    private byte[]? _noncePrefix; // 4B random prefix
    private long _nonceCounter;
    private bool _disposed;

    /// <summary>
    /// True pokud byl úspěšně odvozen sdílený klíč a šifrování je připraveno.
    /// </summary>
    public bool IsReady => _sharedKey != null;

    /// <summary>
    /// Vygeneruje ECDH P-256 key pair a vrátí veřejný klíč jako base64
    /// (65 bytů, uncompressed point).
    /// </summary>
    public string GenerateKeyPair()
    {
        _ecdh = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);

        // Export uncompressed public key (65B: 0x04 + 32B X + 32B Y)
        var parameters = _ecdh.ExportParameters(false);
        var publicKeyBytes = new byte[65];
        publicKeyBytes[0] = 0x04;
        parameters.Q.X!.CopyTo(publicKeyBytes, 1);
        parameters.Q.Y!.CopyTo(publicKeyBytes, 33);

        // Připravit nonce prefix (4B random)
        _noncePrefix = RandomNumberGenerator.GetBytes(4);
        _nonceCounter = 0;

        return Convert.ToBase64String(publicKeyBytes);
    }

    /// <summary>
    /// Odvodí sdílený AES-256 klíč z peer's public key přes ECDH + HKDF.
    /// </summary>
    public void DeriveSharedKey(string peerPublicKeyBase64)
    {
        if (_ecdh == null)
            throw new InvalidOperationException("Key pair not generated. Call GenerateKeyPair() first.");

        var peerBytes = Convert.FromBase64String(peerPublicKeyBase64);
        if (peerBytes.Length != 65 || peerBytes[0] != 0x04)
            throw new ArgumentException("Invalid peer public key format. Expected 65-byte uncompressed point.");

        // Parse uncompressed point → ECParameters
        var peerParams = new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint
            {
                X = peerBytes[1..33],
                Y = peerBytes[33..65]
            }
        };

        using var peerKey = ECDiffieHellman.Create(peerParams);

        // ECDH shared secret
        var sharedSecret = _ecdh.DeriveRawSecretAgreement(peerKey.PublicKey);

        // HKDF: shared_secret → AES-256 key
        var salt = System.Text.Encoding.UTF8.GetBytes(HkdfSalt);
        var info = System.Text.Encoding.UTF8.GetBytes(HkdfInfo);
        _sharedKey = HKDF.DeriveKey(HashAlgorithmName.SHA256, sharedSecret, 32, salt, info);

        // Vyčistit shared secret z paměti
        CryptographicOperations.ZeroMemory(sharedSecret);
    }

    /// <summary>
    /// Šifruje data pomocí AES-256-GCM.
    /// Formát výstupu: [12B nonce][ciphertext][16B tag]
    /// </summary>
    public byte[] Encrypt(byte[] plaintext)
    {
        if (_sharedKey == null)
            throw new InvalidOperationException("Shared key not derived. Complete key exchange first.");

        var nonce = GenerateNonce();
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagSize];

        using var aes = new AesGcm(_sharedKey, TagSize);
        aes.Encrypt(nonce, plaintext, ciphertext, tag);

        // Složit: [nonce][ciphertext][tag]
        var result = new byte[NonceSize + ciphertext.Length + TagSize];
        nonce.CopyTo(result, 0);
        ciphertext.CopyTo(result, NonceSize);
        tag.CopyTo(result, NonceSize + ciphertext.Length);

        return result;
    }

    /// <summary>
    /// Dešifruje data z formátu [12B nonce][ciphertext][16B tag].
    /// </summary>
    public byte[] Decrypt(byte[] encrypted)
    {
        if (_sharedKey == null)
            throw new InvalidOperationException("Shared key not derived. Complete key exchange first.");

        if (encrypted.Length < NonceSize + TagSize)
            throw new ArgumentException("Encrypted data too short.");

        var nonce = encrypted[..NonceSize];
        var ciphertextLength = encrypted.Length - NonceSize - TagSize;
        var ciphertext = encrypted[NonceSize..(NonceSize + ciphertextLength)];
        var tag = encrypted[(NonceSize + ciphertextLength)..];

        var plaintext = new byte[ciphertextLength];

        using var aes = new AesGcm(_sharedKey, TagSize);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return plaintext;
    }

    /// <summary>
    /// Šifruje string a vrátí base64 (pro JSON payload).
    /// </summary>
    public string EncryptToBase64(string plaintext)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(plaintext);
        var encrypted = Encrypt(bytes);
        return Convert.ToBase64String(encrypted);
    }

    /// <summary>
    /// Dešifruje base64 string zpět na plaintext string.
    /// </summary>
    public string DecryptFromBase64(string encryptedBase64)
    {
        var encrypted = Convert.FromBase64String(encryptedBase64);
        var decrypted = Decrypt(encrypted);
        return System.Text.Encoding.UTF8.GetString(decrypted);
    }

    /// <summary>
    /// Resetuje stav pro novou session.
    /// </summary>
    public void Reset()
    {
        if (_sharedKey != null)
        {
            CryptographicOperations.ZeroMemory(_sharedKey);
            _sharedKey = null;
        }
        _ecdh?.Dispose();
        _ecdh = null;
        _noncePrefix = null;
        _nonceCounter = 0;
    }

    /// <summary>
    /// Generuje unikátní nonce: [4B random prefix][8B counter].
    /// </summary>
    private byte[] GenerateNonce()
    {
        var nonce = new byte[NonceSize];
        _noncePrefix!.CopyTo(nonce, 0);
        BitConverter.GetBytes(Interlocked.Increment(ref _nonceCounter)).CopyTo(nonce, 4);
        return nonce;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Reset();
    }
}
