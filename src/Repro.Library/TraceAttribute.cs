using System;
using MethodBoundaryAspect.Fody.Attributes;

namespace Repro.Library
{
    /// <summary>
    /// Minimal aspect: writes a line when a decorated method is entered and exited.
    /// </summary>
    public sealed class TraceAttribute : OnMethodBoundaryAspect
    {
        public override void OnEntry(MethodExecutionArgs args)
        {
            Console.WriteLine($"    [Trace] enter {args.Method.DeclaringType?.Name}.{args.Method.Name}");
        }

        public override void OnExit(MethodExecutionArgs args)
        {
            Console.WriteLine($"    [Trace] exit  {args.Method.DeclaringType?.Name}.{args.Method.Name}");
        }
    }
}
