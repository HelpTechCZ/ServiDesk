namespace RemoteAgent.Service.Streaming;

/// <summary>
/// Automatické řízení kvality streamu na základě RTT (Round-Trip Time).
/// Rolling window posledních 10 měření s hysterezí (3× potvrzení trendu).
/// </summary>
public class AdaptiveQualityController
{
    private readonly Queue<long> _rttHistory = new();
    private const int MaxHistory = 10;

    // Hystereze: trend musí být potvrzen 3× za sebou
    private string _currentQuality = "high";
    private int _currentFps = 30;
    private int _trendCounter = 0;
    private string _trendDirection = ""; // "up" | "down" | ""

    public bool IsEnabled { get; set; } = true;

    /// <summary>
    /// Přidá nové RTT měření do rolling window.
    /// </summary>
    public void UpdateRtt(long rttMs)
    {
        _rttHistory.Enqueue(rttMs);
        while (_rttHistory.Count > MaxHistory)
            _rttHistory.Dequeue();
    }

    /// <summary>
    /// Vrátí doporučenou kvalitu a FPS na základě průměrného RTT.
    /// </summary>
    public (string quality, int fps) GetRecommendedSettings()
    {
        if (!IsEnabled || _rttHistory.Count == 0)
            return (_currentQuality, _currentFps);

        var avgRtt = (long)_rttHistory.Average();
        string targetQuality;
        int targetFps;

        if (avgRtt < 50)
        {
            targetQuality = "high";
            targetFps = 30;
        }
        else if (avgRtt <= 150)
        {
            targetQuality = "medium";
            targetFps = 20;
        }
        else
        {
            targetQuality = "low";
            targetFps = 15;
        }

        // Hystereze – nesnižovat/zvyšovat dokud se trend nepotvrdí 3× za sebou
        if (targetQuality != _currentQuality)
        {
            var direction = GetQualityLevel(targetQuality) > GetQualityLevel(_currentQuality) ? "up" : "down";
            if (direction == _trendDirection)
            {
                _trendCounter++;
            }
            else
            {
                _trendDirection = direction;
                _trendCounter = 1;
            }

            if (_trendCounter >= 3)
            {
                _currentQuality = targetQuality;
                _currentFps = targetFps;
                _trendCounter = 0;
                _trendDirection = "";
            }
        }
        else
        {
            // RTT se stabilizovalo na aktuální úrovni
            _trendCounter = 0;
            _trendDirection = "";
        }

        return (_currentQuality, _currentFps);
    }

    /// <summary>
    /// Průměrné RTT z rolling window (pro zobrazení ve vieweru).
    /// </summary>
    public long AverageRtt => _rttHistory.Count > 0 ? (long)_rttHistory.Average() : 0;

    private static int GetQualityLevel(string quality) => quality switch
    {
        "low" => 0,
        "medium" => 1,
        "high" => 2,
        _ => 1
    };
}
