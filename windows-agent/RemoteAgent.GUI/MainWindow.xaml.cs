using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using RemoteAgent.GUI.ViewModels;

namespace RemoteAgent.GUI;

public class BoolToCheckingTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is true ? "Kontroluji..." : "Zkontrolovat aktualizace";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotImplementedException();
    }
}

public partial class MainWindow : Window
{
    private System.Windows.Forms.NotifyIcon? _notifyIcon;

    public MainWindow()
    {
        // Registrovat convertery
        Resources.Add("BoolToVisConverter", new BooleanToVisibilityConverter());
        Resources.Add("BoolToCheckingTextConverter", new BoolToCheckingTextConverter());

        InitializeComponent();
        InitializeTrayIcon();

        Loaded += async (_, _) =>
        {
            if (DataContext is MainViewModel vm)
            {
                vm.RequestMinimizeToTray = () => Dispatcher.Invoke(() =>
                {
                    WindowState = WindowState.Minimized;
                });
                await vm.InitializeAsync();
            }
        };
    }

    private void InitializeTrayIcon()
    {
        // Načíst ikonu z embedded resource
        var iconStream = System.Windows.Application.GetResourceStream(
            new Uri("pack://application:,,,/Assets/app.ico"))?.Stream;

        _notifyIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = iconStream != null ? new System.Drawing.Icon(iconStream) : System.Drawing.SystemIcons.Application,
            Text = "ServiDesk – Vzdálená podpora",
            Visible = false
        };

        _notifyIcon.DoubleClick += (_, _) => RestoreFromTray();

        var contextMenu = new System.Windows.Forms.ContextMenuStrip();
        contextMenu.Items.Add("Otevřít ServiDesk", null, (_, _) => RestoreFromTray());
        contextMenu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        contextMenu.Items.Add("Ukončit", null, (_, _) =>
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
            System.Windows.Application.Current.Shutdown();
        });
        _notifyIcon.ContextMenuStrip = contextMenu;
    }

    protected override void OnStateChanged(EventArgs e)
    {
        base.OnStateChanged(e);

        if (WindowState == WindowState.Minimized)
        {
            Hide();
            if (_notifyIcon != null)
                _notifyIcon.Visible = true;
        }
    }

    private void RestoreFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
        if (_notifyIcon != null)
            _notifyIcon.Visible = false;
    }

    protected override void OnClosed(EventArgs e)
    {
        _notifyIcon?.Dispose();
        _notifyIcon = null;
        base.OnClosed(e);
    }

    private async void SaveUnattendedPassword_Click(object sender, RoutedEventArgs e)
    {
        if (DataContext is not MainViewModel vm) return;

        var password = UnattendedPasswordBox.Password;
        var confirm = UnattendedPasswordConfirmBox.Password;

        if (string.IsNullOrWhiteSpace(password))
        {
            vm.UnattendedStatusText = "Zadejte heslo.";
            return;
        }

        if (password.Length < 6)
        {
            vm.UnattendedStatusText = "Heslo musí mít alespoň 6 znaků.";
            return;
        }

        if (password != confirm)
        {
            vm.UnattendedStatusText = "Hesla se neshodují.";
            return;
        }

        await vm.SaveUnattendedPassword(password);
        UnattendedPasswordBox.Clear();
        UnattendedPasswordConfirmBox.Clear();
    }
}
