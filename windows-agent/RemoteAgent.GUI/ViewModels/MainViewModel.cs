using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows.Input;
using Microsoft.Win32;
using RemoteAgent.GUI.IPC;
using RemoteAgent.Shared.Messages;

namespace RemoteAgent.GUI.ViewModels;

public enum ViewState
{
    Idle,           // Formulář + tlačítko "Povolit připojení"
    Connecting,     // Připojování ke službě/relay
    Waiting,        // Čeká na technika
    Connected,      // Technik je připojen
    Disconnected,   // Session ukončena
    Error           // Chyba
}

public class MainViewModel : INotifyPropertyChanged
{
    private readonly PipeClient _pipeClient;

    private string _customerName = "";
    private string _problemDescription = "";
    private string _statusText = "Nepřipojeno";
    private ViewState _currentState = ViewState.Idle;
    private string _adminName = "";
    private string _errorMessage = "";

    public string ComputerName { get; } = Environment.MachineName;

    public string VersionText { get; } = $"v{System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "?"}";


    public string CustomerName
    {
        get => _customerName;
        set { _customerName = value; OnPropertyChanged(); OnPropertyChanged(nameof(CanRequestSupport)); }
    }

    public string ProblemDescription
    {
        get => _problemDescription;
        set { _problemDescription = value; OnPropertyChanged(); }
    }

    public string StatusText
    {
        get => _statusText;
        set { _statusText = value; OnPropertyChanged(); }
    }

    public ViewState CurrentState
    {
        get => _currentState;
        set
        {
            _currentState = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanRequestSupport));
            OnPropertyChanged(nameof(IsIdle));
            OnPropertyChanged(nameof(IsWaiting));
            OnPropertyChanged(nameof(IsConnected));
            OnPropertyChanged(nameof(IsDisconnected));
            OnPropertyChanged(nameof(ShowForm));
            OnPropertyChanged(nameof(IsSessionEnded));
        }
    }

    public string AdminName
    {
        get => _adminName;
        set { _adminName = value; OnPropertyChanged(); }
    }

    public string ErrorMessage
    {
        get => _errorMessage;
        set { _errorMessage = value; OnPropertyChanged(); }
    }

    // Stav-dependent properties
    public bool CanRequestSupport => !string.IsNullOrWhiteSpace(CustomerName) && CurrentState == ViewState.Idle;
    public bool IsIdle => CurrentState == ViewState.Idle;
    public bool IsWaiting => CurrentState == ViewState.Waiting || CurrentState == ViewState.Connecting;
    public bool IsConnected => CurrentState == ViewState.Connected;
    public bool IsDisconnected => CurrentState == ViewState.Disconnected;
    public bool ShowForm => CurrentState == ViewState.Idle;
    public bool IsSessionEnded => CurrentState == ViewState.Disconnected;

    private string _sessionEndReason = "";
    public string SessionEndReason
    {
        get => _sessionEndReason;
        set { _sessionEndReason = value; OnPropertyChanged(); }
    }

    // Update banner
    private bool _updateAvailable;
    public bool UpdateAvailable
    {
        get => _updateAvailable;
        set { _updateAvailable = value; OnPropertyChanged(); }
    }

    private string _updateVersion = "";
    public string UpdateVersion
    {
        get => _updateVersion;
        set { _updateVersion = value; OnPropertyChanged(); }
    }

    // Unattended access
    private string _unattendedStatusText = "";
    public string UnattendedStatusText
    {
        get => _unattendedStatusText;
        set { _unattendedStatusText = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasUnattendedStatus)); }
    }
    public bool HasUnattendedStatus => !string.IsNullOrEmpty(UnattendedStatusText);

    private bool _isUnattendedConfigured;
    public bool IsUnattendedConfigured
    {
        get => _isUnattendedConfigured;
        set
        {
            _isUnattendedConfigured = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ShowPasswordForm));
            OnPropertyChanged(nameof(ShowChangePasswordButton));
        }
    }

    private bool _isChangingPassword;
    public bool IsChangingPassword
    {
        get => _isChangingPassword;
        set
        {
            _isChangingPassword = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ShowPasswordForm));
            OnPropertyChanged(nameof(ShowChangePasswordButton));
        }
    }

    public bool ShowPasswordForm => !IsUnattendedConfigured || IsChangingPassword;
    public bool ShowChangePasswordButton => IsUnattendedConfigured && !IsChangingPassword;

    public ICommand ChangePasswordCommand { get; }
    public ICommand DisableUnattendedCommand { get; }

    public async Task SaveUnattendedPassword(string password)
    {
        if (!_pipeClient.IsConnected)
        {
            UnattendedStatusText = "Služba není spuštěna.";
            return;
        }
        UnattendedStatusText = "Ukládám...";
        await _pipeClient.SetUnattendedPasswordAsync(password);
        IsUnattendedConfigured = true;
        IsChangingPassword = false;
    }

    private async Task CheckForUpdate()
    {
        if (!_pipeClient.IsConnected)
        {
            UpdateCheckMessage = "Služba není spuštěna.";
            return;
        }
        IsCheckingUpdate = true;
        UpdateCheckMessage = "";
        await _pipeClient.SendCommandAsync(IpcCommand.CheckUpdate);
    }

    private async Task DisableUnattendedAccess()
    {
        if (!_pipeClient.IsConnected)
        {
            UnattendedStatusText = "Služba není spuštěna.";
            return;
        }
        await _pipeClient.SendCommandAsync(IpcCommand.DisableUnattendedAccess, null);
    }

    // Autostart
    private const string RunRegistryKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "ServiDesk";

    private bool _startWithWindows;
    public bool StartWithWindows
    {
        get => _startWithWindows;
        set
        {
            if (_startWithWindows == value) return;
            _startWithWindows = value;
            OnPropertyChanged();
            SetStartWithWindows(value);
        }
    }

    private void LoadStartWithWindows()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunRegistryKey, false);
            _startWithWindows = key?.GetValue(RunValueName) != null;
        }
        catch { _startWithWindows = false; }
    }

    private void SetStartWithWindows(bool enable)
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
            if (key == null) return;
            if (enable)
            {
                var exePath = Environment.ProcessPath ?? System.Reflection.Assembly.GetExecutingAssembly().Location;
                key.SetValue(RunValueName, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(RunValueName, false);
            }
        }
        catch { /* Registry write may fail without admin */ }
    }

    // Chat
    public ObservableCollection<ChatMessagePayload> ChatMessages { get; } = new();

    private string _chatInput = "";
    public string ChatInput
    {
        get => _chatInput;
        set { _chatInput = value; OnPropertyChanged(); }
    }

    // Update check
    private bool _isCheckingUpdate;
    public bool IsCheckingUpdate
    {
        get => _isCheckingUpdate;
        set { _isCheckingUpdate = value; OnPropertyChanged(); }
    }

    private string _updateCheckMessage = "";
    public string UpdateCheckMessage
    {
        get => _updateCheckMessage;
        set { _updateCheckMessage = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasUpdateCheckMessage)); }
    }
    public bool HasUpdateCheckMessage => !string.IsNullOrEmpty(UpdateCheckMessage);

    // Commands
    public ICommand RequestSupportCommand { get; }
    public ICommand CancelCommand { get; }
    public ICommand DisconnectCommand { get; }
    public ICommand NewRequestCommand { get; }
    public ICommand ReconnectCommand { get; }
    public ICommand BackToIdleCommand { get; }
    public ICommand SendChatCommand { get; }
    public ICommand CheckUpdateCommand { get; }

    public MainViewModel()
    {
        _pipeClient = new PipeClient();
        _pipeClient.OnNotification += OnServiceNotification;
        _pipeClient.OnDisconnected += () =>
        {
            CurrentState = ViewState.Error;
            StatusText = "Služba se odpojila";
            ErrorMessage = "Služba RemoteAgent není spuštěna.";
        };

        RequestSupportCommand = new RelayCommand(async () => await RequestSupport(), () => CanRequestSupport);
        CancelCommand = new RelayCommand(async () => await Cancel());
        DisconnectCommand = new RelayCommand(async () => await Disconnect());
        NewRequestCommand = new RelayCommand(() => { CurrentState = ViewState.Idle; StatusText = "Nepřipojeno"; return Task.CompletedTask; });
        ReconnectCommand = new RelayCommand(async () => await Reconnect());
        BackToIdleCommand = new RelayCommand(() => { CurrentState = ViewState.Idle; StatusText = "Nepřipojeno"; ChatMessages.Clear(); return Task.CompletedTask; });
        SendChatCommand = new RelayCommand(async () => await SendChat(), () => !string.IsNullOrWhiteSpace(ChatInput) && IsConnected);
        ChangePasswordCommand = new RelayCommand(() => { IsChangingPassword = true; return Task.CompletedTask; });
        DisableUnattendedCommand = new RelayCommand(async () => await DisableUnattendedAccess());
        CheckUpdateCommand = new RelayCommand(async () => await CheckForUpdate(), () => !IsCheckingUpdate);

        // Načíst stav vzdáleného přístupu z configu
        try
        {
            var config = RemoteAgent.Shared.Config.AgentConfig.Load();
            _isUnattendedConfigured = config.UnattendedAccessEnabled;
        }
        catch { _isUnattendedConfigured = false; }

        // Načíst stav autostartu z registru
        LoadStartWithWindows();
    }

    public async Task InitializeAsync()
    {
        try
        {
            await _pipeClient.ConnectAsync();

            // Pokud je vzdálený přístup aktivní, připojit se k relay (agent bude viditelný jako online)
            if (_isUnattendedConfigured)
            {
                await _pipeClient.ConnectRelayAsync(Environment.MachineName);
            }
        }
        catch
        {
            CurrentState = ViewState.Error;
            StatusText = "Nelze se připojit ke službě";
            ErrorMessage = "Služba RemoteAgent není spuštěna. Spusťte ji jako administrátor.";
        }
    }

    private async Task RequestSupport()
    {
        CurrentState = ViewState.Connecting;
        StatusText = "Připojuji se...";

        // Nejprve připojit k relay
        await _pipeClient.ConnectRelayAsync(CustomerName);

        // Počkat na potvrzení připojení, pak poslat žádost
        // (zpracuje se v OnServiceNotification)
    }

    private async Task Cancel()
    {
        await _pipeClient.CancelSupportAsync();
        CurrentState = ViewState.Idle;
        StatusText = "Žádost zrušena";
    }

    /// <summary>
    /// Nastavit z MainWindow pro minimalizaci do tray.
    /// </summary>
    public Action? RequestMinimizeToTray { get; set; }

    /// <summary>
    /// Nastavit z MainWindow pro zavření aplikace.
    /// </summary>
    public Action? RequestCloseApp { get; set; }

    private async Task Disconnect()
    {
        await _pipeClient.DisconnectAsync();

        if (_isUnattendedConfigured)
        {
            // Znovu připojit k relay (agent zůstane online pro vzdálený přístup)
            CurrentState = ViewState.Idle;
            StatusText = "Vzdálený přístup aktivní";
            await _pipeClient.ConnectRelayAsync(Environment.MachineName);
            RequestMinimizeToTray?.Invoke();
        }
        else
        {
            // Bez vzdáleného přístupu – zavřít aplikaci
            RequestCloseApp?.Invoke();
        }
    }

    private async Task Reconnect()
    {
        CurrentState = ViewState.Connecting;
        StatusText = "Připojuji se...";
        await _pipeClient.ConnectRelayAsync(CustomerName);
    }

    private async Task SendChat()
    {
        if (string.IsNullOrWhiteSpace(ChatInput)) return;
        var msg = new ChatMessagePayload
        {
            Message = ChatInput,
            Sender = "customer",
            Timestamp = DateTime.UtcNow.ToString("o")
        };
        ChatMessages.Add(msg);
        await _pipeClient.SendCommandAsync(IpcCommand.SendChat, msg);
        ChatInput = "";
    }

    private void OnServiceNotification(string type, JsonElement? payload)
    {
        // Musí se volat na UI vlákně
        System.Windows.Application.Current?.Dispatcher.Invoke(() =>
        {
            switch (type)
            {
                case IpcNotification.StatusUpdate:
                    var status = payload?.GetProperty("status").GetString();
                    switch (status)
                    {
                        case "connected":
                            // Připojeno k relay → poslat žádost jen pokud uživatel klikl "Povolit připojení"
                            if (CurrentState == ViewState.Connecting)
                            {
                                _ = _pipeClient.RequestSupportAsync(CustomerName, ProblemDescription);
                                CurrentState = ViewState.Waiting;
                                StatusText = "Čekám na technika...";
                            }
                            break;
                        case "disconnected":
                            CurrentState = ViewState.Disconnected;
                            SessionEndReason = "Ztráta spojení se serverem.";
                            StatusText = SessionEndReason;
                            break;
                        case "unattended_password_set":
                            UnattendedStatusText = payload?.GetProperty("message").GetString()
                                                   ?? "Heslo uloženo.";
                            break;
                        case "unattended_disabled":
                            IsUnattendedConfigured = false;
                            IsChangingPassword = false;
                            UnattendedStatusText = "";
                            break;
                    }
                    break;

                case IpcNotification.SessionAccepted:
                    AdminName = payload?.GetProperty("admin_name").GetString() ?? "Technik";
                    CurrentState = ViewState.Connected;
                    StatusText = $"{AdminName} je připojen a vidí vaši obrazovku";
                    break;

                case IpcNotification.SessionEnded:
                    var reason = payload?.GetProperty("reason").GetString();
                    var endedBy = "";
                    try { endedBy = payload?.GetProperty("ended_by").GetString() ?? ""; } catch { }

                    if (_isUnattendedConfigured)
                    {
                        // Vzdálený přístup aktivní → znovu připojit k relay a minimalizovat
                        CurrentState = ViewState.Idle;
                        StatusText = "Vzdálený přístup aktivní";
                        _ = _pipeClient.ConnectRelayAsync(Environment.MachineName);
                        RequestMinimizeToTray?.Invoke();
                    }
                    else
                    {
                        // Bez vzdáleného přístupu → zavřít aplikaci
                        RequestCloseApp?.Invoke();
                    }
                    break;

                case IpcNotification.ChatMessage:
                    var chatMsg = JsonSerializer.Deserialize<ChatMessagePayload>(payload?.GetRawText() ?? "{}");
                    if (chatMsg != null) ChatMessages.Add(chatMsg);
                    break;

                case IpcNotification.FileIncoming:
                    var filePayload = JsonSerializer.Deserialize<FileIncomingPayload>(payload?.GetRawText() ?? "{}");
                    if (filePayload != null)
                    {
                        HandleFileIncoming(filePayload);
                    }
                    break;

                case IpcNotification.FileReceived:
                    var receivedPayload = JsonSerializer.Deserialize<FileReceivedPayload>(payload?.GetRawText() ?? "{}");
                    if (receivedPayload != null)
                    {
                        StatusText = $"Soubor uložen: {receivedPayload.FileName}";
                    }
                    break;

                case IpcNotification.UpdateAvailable:
                    var updatePayload = JsonSerializer.Deserialize<UpdateAvailablePayload>(payload?.GetRawText() ?? "{}");
                    if (updatePayload != null)
                    {
                        UpdateAvailable = true;
                        UpdateVersion = updatePayload.Version;
                        UpdateCheckMessage = "";
                    }
                    IsCheckingUpdate = false;
                    break;

                case IpcNotification.UpdateCheckResult:
                    var checkResult = JsonSerializer.Deserialize<UpdateCheckResultPayload>(payload?.GetRawText() ?? "{}");
                    if (checkResult != null)
                    {
                        UpdateCheckMessage = checkResult.Message;
                    }
                    IsCheckingUpdate = false;
                    break;

                case IpcNotification.Error:
                    var code = payload?.GetProperty("code").GetString();
                    var msg = payload?.GetProperty("message").GetString();
                    ErrorMessage = $"{code}: {msg}";
                    StatusText = "Chyba";
                    break;
            }
        });
    }

    // ── File Transfer ──

    private void HandleFileIncoming(FileIncomingPayload file)
    {
        var sizeMB = file.FileSize / (1024.0 * 1024.0);
        var sizeText = sizeMB >= 1 ? $"{sizeMB:F1} MB" : $"{file.FileSize / 1024.0:F0} KB";

        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = file.FileName,
            Title = $"Uložit soubor od technika ({sizeText})",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Desktop)
        };

        var ext = System.IO.Path.GetExtension(file.FileName);
        if (!string.IsNullOrEmpty(ext))
        {
            dialog.Filter = $"Soubor (*{ext})|*{ext}|Všechny soubory (*.*)|*.*";
        }

        var savePath = "";
        if (dialog.ShowDialog() == true)
        {
            savePath = dialog.FileName;
            StatusText = $"Přijímám soubor: {file.FileName}...";
        }

        // Poslat cestu zpět do služby (prázdný string = zrušeno)
        _ = _pipeClient.SendCommandAsync(IpcCommand.FileSavePath, new FileSavePathPayload
        {
            TransferId = file.TransferId,
            SavePath = savePath
        });
    }

    // ── INotifyPropertyChanged ──

    public event PropertyChangedEventHandler? PropertyChanged;

    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

/// <summary>
/// Jednoduchý async RelayCommand pro MVVM.
/// </summary>
public class RelayCommand : ICommand
{
    private readonly Func<Task> _execute;
    private readonly Func<bool>? _canExecute;

    public RelayCommand(Func<Task> execute, Func<bool>? canExecute = null)
    {
        _execute = execute;
        _canExecute = canExecute;
    }

    public event EventHandler? CanExecuteChanged
    {
        add => CommandManager.RequerySuggested += value;
        remove => CommandManager.RequerySuggested -= value;
    }

    public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;

    public async void Execute(object? parameter) => await _execute();
}
