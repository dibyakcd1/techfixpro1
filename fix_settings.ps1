
# Read all lines
$lines = Get-Content "d:\Devlopment\git\techfixpro1\lib\screens\settings.dart"

# Build new content
$newContent = @()
# Keep lines 1-1663 (original lines are 1-based, so 0..1662)
$newContent += $lines[0..1662]

# Add our placeholder widget
$newContent += @'
class FirebaseDiagnosticsPage extends StatelessWidget {
  const FirebaseDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Supabase Diagnostics',
      subtitle: 'Coming soon',
      children: [
        _infoBanner(
          'Supabase Diagnostics are under development.\n\n'
          'Please check back later for updates!',
        ),
      ],
    );
  }
}
'@

# Keep lines from 2320 (1-based is 2320, so 0-based 2319) onwards
$newContent += $lines[2319..($lines.Length - 1)]

# Write back to the file
$newContent | Set-Content -Path "d:\Devlopment\git\techfixpro1\lib\screens\settings.dart" -Encoding UTF8

Write-Host "File updated successfully!"
