using System;
using System.Runtime.InteropServices;
using Repro.Library;

namespace Repro.Net8
{
    public static class Program
    {
        public static int Main()
        {
            Console.WriteLine($"Runtime: {RuntimeInformation.FrameworkDescription}");

            var ok = Run("1. [Trace] method woven in this app (net8.0)", () => Add(2, 3).ToString());
            ok &= Run("2. [Trace] method woven in Repro.Library (netstandard2.0)", () => new Greeter().Greet("world"));

            Console.WriteLine(ok ? "RESULT: SUCCESS" : "RESULT: FAILED");
            return ok ? 0 : 1;
        }

        // Woven inside this assembly.
        [Trace]
        private static int Add(int a, int b)
        {
            return a + b;
        }

        private static bool Run(string title, Func<string> action)
        {
            Console.WriteLine(title);
            try
            {
                Console.WriteLine($"    returned: {action()}");
                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"    FAILED: {ex.GetType().FullName}: {ex.Message}");
                for (var inner = ex.InnerException; inner != null; inner = inner.InnerException)
                    Console.WriteLine($"     ---> {inner.GetType().FullName}: {inner.Message}");
                return false;
            }
        }
    }
}
