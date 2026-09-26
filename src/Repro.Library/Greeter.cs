namespace Repro.Library
{
    public class Greeter
    {
        // Woven inside this netstandard2.0 library.
        [Trace]
        public string Greet(string name)
        {
            return $"Hello, {name}!";
        }
    }
}
