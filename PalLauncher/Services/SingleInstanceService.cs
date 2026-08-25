using System;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class SingleInstanceManager : IDisposable
    {
        private const string GuiMutexName = @"Local\PalOdysseyLauncher_GUI_Mutex";
        private const string DaemonMutexName = @"Local\PalOdysseyLauncher_Daemon_Mutex";
        private const string EventName = @"Local\PalOdysseyLauncher_ShowSignal_GUI_Event";

        private readonly ILogService? _logService;
        private Mutex? _mutex;
        private EventWaitHandle? _showEvent;
        private CancellationTokenSource? _listenCts;
        private bool _disposed;

        public bool IsFirstInstance { get; private set; }

        public SingleInstanceManager(ILogService? logService = null)
        {
            _logService = logService;
        }

        public bool TryAcquire(bool isDaemon = false, string? customMutexName = null)
        {
            try
            {
                string targetMutexName = customMutexName ?? (isDaemon ? DaemonMutexName : GuiMutexName);
                _mutex = new Mutex(true, targetMutexName, out bool createdNew);
                IsFirstInstance = createdNew;
                return createdNew;
            }
            catch (Exception ex)
            {
                _logService?.LogWarning($"SingleInstanceManager acquisition check encountered: {ex.Message}", "App");
                IsFirstInstance = true;
                return true;
            }
        }

        public static void SignalExistingInstanceToShowWindow()
        {
            try
            {
                if (EventWaitHandle.TryOpenExisting(EventName, out var existingEvent))
                {
                    existingEvent.Set();
                    existingEvent.Dispose();
                }
            }
            catch { }
        }

        public void StartListeningForShowSignal(Action onShowRequested)
        {
            if (!IsFirstInstance) return;

            try
            {
                _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, EventName);
                _listenCts = new CancellationTokenSource();
                var ct = _listenCts.Token;

                Task.Run(() =>
                {
                    var waitHandles = new WaitHandle[] { _showEvent, ct.WaitHandle };
                    while (!ct.IsCancellationRequested)
                    {
                        int index = WaitHandle.WaitAny(waitHandles);
                        if (index == 0 && !ct.IsCancellationRequested)
                        {
                            try
                            {
                                onShowRequested?.Invoke();
                            }
                            catch (Exception ex)
                            {
                                _logService?.LogWarning($"Error handling show signal: {ex.Message}", "App");
                            }
                        }
                        else
                        {
                            break;
                        }
                    }
                }, ct);
            }
            catch (Exception ex)
            {
                _logService?.LogWarning($"Could not register show signal event: {ex.Message}", "App");
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            try { _listenCts?.Cancel(); } catch { }
            try { _listenCts?.Dispose(); } catch { }
            try { _showEvent?.Dispose(); } catch { }

            if (_mutex != null)
            {
                try
                {
                    if (IsFirstInstance)
                    {
                        _mutex.ReleaseMutex();
                    }
                }
                catch { }
                finally
                {
                    _mutex.Dispose();
                    _mutex = null;
                }
            }
        }
    }
}