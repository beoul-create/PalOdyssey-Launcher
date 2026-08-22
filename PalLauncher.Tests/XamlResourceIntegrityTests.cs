using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using Xunit;

namespace PalLauncher.Tests
{
    public class XamlResourceIntegrityTests
    {
        [Fact]
        public void AllStaticResourceReferences_InAllViews_AreDefinedInResourceDictionaries()
        {
            string projectDir = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "PalLauncher"));
            string stylesDir = Path.Combine(projectDir, "Styles");
            string viewsDir = Path.Combine(projectDir, "Views");

            var definedKeys = new HashSet<string>(StringComparer.Ordinal);

            // Collect all defined keys from Styles and App.xaml
            var sourceFiles = new List<string>(Directory.GetFiles(stylesDir, "*.xaml", SearchOption.AllDirectories));
            string appXaml = Path.Combine(projectDir, "App.xaml");
            if (File.Exists(appXaml)) sourceFiles.Add(appXaml);

            foreach (var file in sourceFiles)
            {
                string content = File.ReadAllText(file);
                var matches = Regex.Matches(content, @"x:Key\s*=\s*""([^""]+)""");
                foreach (Match m in matches)
                {
                    definedKeys.Add(m.Groups[1].Value);
                }
            }

            // System / standard resources
            definedKeys.Add("SystemControlBackgroundAltHighBrush");

            // Verify all Views and Styles for StaticResource references
            var missingKeys = new List<string>();

            var allXamlFiles = Directory.GetFiles(projectDir, "*.xaml", SearchOption.AllDirectories);
            foreach (var file in allXamlFiles)
            {
                string content = File.ReadAllText(file);

                // Add local keys
                var localMatches = Regex.Matches(content, @"x:Key\s*=\s*""([^""]+)""");
                var currentFileKeys = new HashSet<string>(definedKeys, StringComparer.Ordinal);
                foreach (Match m in localMatches)
                {
                    currentFileKeys.Add(m.Groups[1].Value);
                }

                var refMatches = Regex.Matches(content, @"StaticResource\s+([^},""\s]+)");
                foreach (Match m in refMatches)
                {
                    string key = m.Groups[1].Value;
                    if (!currentFileKeys.Contains(key))
                    {
                        missingKeys.Add($"{Path.GetFileName(file)}: Missing StaticResource '{key}'");
                    }
                }
            }

            Assert.Empty(missingKeys);
        }
    }
}
