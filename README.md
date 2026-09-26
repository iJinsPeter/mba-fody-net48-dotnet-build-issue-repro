# MethodBoundaryAspect.Fody: .NET Framework assemblies built with `dotnet build` fail at runtime

This is a minimal reproduction of a bug in
[MethodBoundaryAspect.Fody](https://github.com/vescon/MethodBoundaryAspect.Fody) (tested with **2.0.150**,
the latest release at the time of writing, together with Fody 6.9.3).

Take an SDK-style project that targets **.NET Framework** (for example `net48`) and uses MethodBoundaryAspect.Fody:

- Build it with **`MSBuild.exe`** (Visual Studio) and it works.
- Build it with **`dotnet build`** (or `dotnet test`, or anything else that uses Core MSBuild) and the build
  succeeds, but the first call to a woven method throws:

```
System.TypeInitializationException: The type initializer for 'OnMethodBoundaryAspectCompile.MethodInfos' threw an exception.
 ---> System.IO.FileNotFoundException: Could not load file or assembly 'System.Private.CoreLib, Version=10.0.0.0,
      Culture=neutral, PublicKeyToken=7cec85d7bea7798e' or one of its dependencies. The system cannot find the file specified.
```

The `System.Private.CoreLib` version in the message matches the .NET SDK that ran the build (8.0.0.0, 10.0.0.0, …).

## What's in the repo

| Project | Target | Contains |
|---|---|---|
| `src/Repro.Library` | `netstandard2.0` | The aspect (`TraceAttribute : OnMethodBoundaryAspect`) and one woven method (`Greeter.Greet`) |
| `src/Repro.Net48` | `net48` | Console app with its own woven method (`Program.Add`); also calls `Greeter.Greet` |
| `src/Repro.Net8` | `net8.0` | Same console app for .NET 8 |

Each app calls its own woven method and then the library's woven method, and prints whether each call worked.
Package versions are set in [`Directory.Build.props`](Directory.Build.props). [`nuget.config`](nuget.config)
restores from nuget.org only.

## Requirements

- Windows with .NET Framework 4.8
- .NET SDK 8 or later, plus the .NET 8 runtime
- Visual Studio 2022+ or Build Tools (only for the `MSBuild.exe` comparison)

## Running the repro

```powershell
./repro.ps1                  # dotnet build and MSBuild.exe, one after the other
./repro.ps1 -Build dotnet    # only dotnet build
./repro.ps1 -Build msbuild   # only MSBuild.exe
```

For each build host the script deletes `bin`/`obj`, builds `Repro.sln` in Release, reports which woven
assemblies reference `System.Private.CoreLib`, and runs both apps.

To do the same by hand:

```powershell
dotnet build Repro.sln -c Release
src\Repro.Net48\bin\Release\net48\Repro.Net48.exe           # fails
dotnet src\Repro.Net8\bin\Release\net8.0\Repro.Net8.dll     # works
```

## Results

| Build host | Woven assemblies reference `System.Private.CoreLib` | net48 app | net8.0 app |
|---|---|---|---|
| `dotnet build` (Core MSBuild) | yes, all three | **FAILED** | OK |
| `MSBuild.exe` (.NET Framework MSBuild) | no | OK | OK |

Output of the net48 app after `dotnet build`:

```
Runtime: .NET Framework 4.8.9345.0
1. [Trace] method woven in this app (net48)
    FAILED: System.TypeInitializationException: The type initializer for 'OnMethodBoundaryAspectCompile.MethodInfos' threw an exception.
     ---> System.IO.FileNotFoundException: Could not load file or assembly 'System.Private.CoreLib, Version=10.0.0.0, ...
2. [Trace] method woven in Repro.Library (netstandard2.0)
    FAILED: System.TypeInitializationException: The type initializer for 'OnMethodBoundaryAspectCompile.MethodInfos' threw an exception.
     ---> System.IO.FileNotFoundException: Could not load file or assembly 'System.Private.CoreLib, Version=10.0.0.0, ...
RESULT: FAILED
```

## Why it happens

1. **Fody runs the weaver on the runtime of the build host.** `MSBuild.exe` runs on .NET Framework, so the
   weaver's core library is `mscorlib`. `dotnet build` runs on .NET, so the weaver's core library is
   `System.Private.CoreLib`.
2. **MethodBoundaryAspect.Fody imports some framework members from the weaver's own runtime, not from the
   assembly being woven.** In `MethodInfoCompileTimeWeaver`, `MethodBase.GetMethodFromHandle` is imported like this:

   ```csharp
   _mainModule.ImportReference(typeof(MethodBase).GetMethod("GetMethodFromHandle", new[] { typeof(RuntimeMethodHandle) }));
   ```

   Under `dotnet build`, `typeof(MethodBase)` lives in `System.Private.CoreLib`, so the woven IL calls
   `[System.Private.CoreLib]System.Reflection.MethodBase::GetMethodFromHandle(...)`.
3. **The call sits in a generated static constructor.** The weaver adds a class
   `OnMethodBoundaryAspectCompile.MethodInfos` that caches one `MethodBase` per woven method. Its static
   constructor calls `GetMethodFromHandle`. The first woven method that runs triggers that constructor, and on
   .NET Framework it throws because `System.Private.CoreLib` doesn't exist there.
4. **Other imported framework types leave an unused reference behind.** `ReferenceFinder.GetTypeReference`
   imports types with `ModuleDefinition.ImportReference(typeof(...))` and then points them at the target's core
   library. Cecil has already added the weaver's core library to `AssemblyReferences` by then, so a
   `System.Private.CoreLib` assembly reference stays in the output. Nothing uses it, so it doesn't crash on its own.

### Why the .NET 8 app and the netstandard2.0 library work there

After `dotnet build`, the net8.0 app and the library also contain `System.Private.CoreLib` references (see the
table). On .NET (Core), `System.Private.CoreLib` is always the runtime's own core library, and the runtime binds
the name no matter which version is recorded. So the wrong reference goes unnoticed on .NET 8, but breaks as soon
as the same assembly runs on .NET Framework. That's why `Repro.Library` works in the net8.0 app and fails in the
net48 app, even though it's the same file.

On .NET the wrong reference can still cause trouble. For example,
[vescon/MethodBoundaryAspect.Fody#113](https://github.com/vescon/MethodBoundaryAspect.Fody/issues/113) reports a
`net6.0` app built with the .NET 7 SDK that references `System.Private.CoreLib, Version=7.0.0.0`, which breaks
debugger evaluation. It has the same root cause.

## Workarounds

- Build .NET Framework projects that use MethodBoundaryAspect.Fody with `MSBuild.exe` instead of `dotnet build`.
- Setting `DisableCompileTimeMethodInfos` does not help. It is a property on `ModuleWeaver` that is never
  read from `FodyWeavers.xml`.

## Proposed fix

[iJinsPeter/MethodBoundaryAspect.Fody#1](https://github.com/iJinsPeter/MethodBoundaryAspect.Fody/pull/1)
resolves `GetMethodFromHandle` from the target module's `TypeSystem.CoreLibrary`. It also adds a Cecil reflection
importer that maps the weaver's core library to the target's core library, so no `System.Private.CoreLib`
reference is created. With a local build of that branch, both apps in this repo work after `dotnet build`, and
no woven assembly references `System.Private.CoreLib`.

To try another package version once one is available:

```powershell
./repro.ps1 -MethodBoundaryAspectFodyVersion <version>
```
