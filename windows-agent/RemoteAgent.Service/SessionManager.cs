namespace RemoteAgent.Service;

/// <summary>
/// Stav session agenta – životní cyklus.
/// </summary>
public enum SessionState
{
    Idle,           // Žádná aktivní session
    Registered,     // Připojen k relay, čeká na pokyn z GUI
    Waiting,        // Zákazník klikl "Povolit", čeká na admina
    Streaming,      // Aktivní session – posílá video, přijímá input
    Disconnecting   // Ukončování session
}

/// <summary>
/// Řídí životní cyklus session na straně agenta.
/// </summary>
public class AgentSessionManager
{
    private SessionState _state = SessionState.Idle;
    private readonly object _lock = new();

    public SessionState State
    {
        get { lock (_lock) return _state; }
    }

    public string? SessionId { get; private set; }
    public string? AdminName { get; private set; }

    public event Action<SessionState, SessionState>? OnStateChanged;

    public bool TransitionTo(SessionState newState)
    {
        lock (_lock)
        {
            var valid = (_state, newState) switch
            {
                (SessionState.Idle, SessionState.Registered) => true,
                (SessionState.Registered, SessionState.Waiting) => true,
                (SessionState.Waiting, SessionState.Streaming) => true,
                (SessionState.Streaming, SessionState.Disconnecting) => true,
                (SessionState.Disconnecting, SessionState.Idle) => true,
                // Resetování z libovolného stavu
                (_, SessionState.Idle) => true,
                // Reconnect
                (SessionState.Idle, SessionState.Waiting) => true,
                _ => false
            };

            if (!valid) return false;

            var oldState = _state;
            _state = newState;
            OnStateChanged?.Invoke(oldState, newState);
            return true;
        }
    }

    public void SetSessionId(string sessionId) => SessionId = sessionId;
    public void SetAdminName(string adminName) => AdminName = adminName;

    public void Reset()
    {
        SessionId = null;
        AdminName = null;
        TransitionTo(SessionState.Idle);
    }
}
