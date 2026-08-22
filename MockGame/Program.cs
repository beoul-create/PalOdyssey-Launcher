using System;
using System.IO;
using System.Threading;

namespace MockGame
{
    internal class Program
    {
        static void Main(string[] args)
        {
            Console.Title = "Palworld (Simulated Game Client)";
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine(@"
  ██████╗  █████╗ ██╗     ██╗    ██╗ ██████╗ ██████╗ ██╗     ██████╗ 
  ██╔══██╗██╔══██╗██║     ██║    ██║██╔═══██╗██╔══██╗██║     ██╔══██╗
  ██████╔╝███████║██║     ██║ █╗ ██║██║   ██║██████╔╝██║     ██║  ██║
  ██╔═══╝ ██╔══██║██║     ██║███╗██║██║   ██║██╔══██╗██║     ██║  ██║
  ██║     ██║  ██║███████╗╚███╔███╔╝╚██████╔╝██║  ██║███████╗██████╔╝
  ╚═╝     ╚═╝  ╚═╝╚══════╝ ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═════╝ 
            ");
            Console.ResetColor();
            Console.WriteLine("==================================================================");
            Console.WriteLine($"[Palworld Engine] PID: {Environment.ProcessId}");
            Console.WriteLine($"[Palworld Engine] Working Directory: {Environment.CurrentDirectory}");
            Console.WriteLine($"[Palworld Engine] Command Arguments ({args.Length}):");

            foreach (var arg in args)
            {
                Console.WriteLine($"   --> {arg}");
            }

            Console.WriteLine("==================================================================");
            Console.WriteLine("[Palworld Engine] Scanning for Content Paks...");

            string paksDir = Path.Combine(Environment.CurrentDirectory, "Pal", "Content", "Paks");
            if (Directory.Exists(paksDir))
            {
                var files = Directory.GetFiles(paksDir, "*.pak", SearchOption.AllDirectories);
                Console.WriteLine($"[Palworld Engine] Loaded {files.Length} pak file(s):");
                foreach (var file in files)
                {
                    Console.WriteLine($"   [PAK] {Path.GetFileName(file)}");
                }
            }
            else
            {
                Console.WriteLine("[Palworld Engine] No Paks directory found at: " + paksDir);
            }

            Console.WriteLine("==================================================================");
            Console.WriteLine("[Palworld Engine] Game is running. Press 'Q' or close window to exit.");
            Console.WriteLine("==================================================================");

            // Keep process running for testing
            for (int i = 0; i < 30; i++)
            {
                if (Console.KeyAvailable)
                {
                    var key = Console.ReadKey(true);
                    if (key.Key == ConsoleKey.Q) break;
                }
                Thread.Sleep(1000);
            }

            Console.WriteLine("[Palworld Engine] Game shutdown complete.");
        }
    }
}
