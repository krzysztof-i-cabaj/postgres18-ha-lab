# ==============================================================================
# Tytul:        Scancode.Tests.ps1
# Opis:         Pester testy mappera scancode (US keyboard, set 1).
#               Gating: musi byc zielony przed jakimkolwiek bootem VMki.
# Description [EN]: Pester tests for the scancode mapper (US keyboard, set 1).
#               Gating: must be green before any VM boot.
#
# Autor:        KCB Kris
# Data:         2026-05-02
# Wersja:       1.0
# <repo>:       <repo>
# Konwencje:    <repo>/SETTINGS.md
#
# Wymagania [PL]:    - PowerShell 5.1+, Pester 5+
#                      Install-Module Pester -Force -SkipPublisherCheck
# Requirements [EN]: - PowerShell 5.1+, Pester 5+
#
# Uzycie [PL]:       Invoke-Pester host/tests/Scancode.Tests.ps1 -Output Detailed
# Usage [EN]:        Invoke-Pester host/tests/Scancode.Tests.ps1 -Output Detailed
# ==============================================================================

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..\modules\Scancode.psm1'
    Import-Module $script:ModulePath -Force -DisableNameChecking
}

Describe 'Convert-CharToScancode -- single chars' {

    It 'maps lowercase a -> 1e/9e' {
        $r = Convert-CharToScancode -Char 'a'
        $r.Press   | Should -Be '1e'
        $r.Release | Should -Be '9e'
    }

    It 'maps uppercase A -> shift+a (2a 1e / 9e aa)' {
        $r = Convert-CharToScancode -Char 'A'
        $r.Press   | Should -Be '2a 1e'
        $r.Release | Should -Be '9e aa'
    }

    It 'maps digit 0 -> 0b/8b' {
        $r = Convert-CharToScancode -Char '0'
        $r.Press   | Should -Be '0b'
        $r.Release | Should -Be '8b'
    }

    It 'maps space -> 39/b9' {
        $r = Convert-CharToScancode -Char ' '
        $r.Press   | Should -Be '39'
        $r.Release | Should -Be 'b9'
    }

    It 'maps slash / -> 35/b5' {
        $r = Convert-CharToScancode -Char '/'
        $r.Press   | Should -Be '35'
        $r.Release | Should -Be 'b5'
    }

    It 'maps dot . -> 34/b4' {
        $r = Convert-CharToScancode -Char '.'
        $r.Press   | Should -Be '34'
        $r.Release | Should -Be 'b4'
    }

    It 'maps equals = -> 0d/8d' {
        $r = Convert-CharToScancode -Char '='
        $r.Press   | Should -Be '0d'
        $r.Release | Should -Be '8d'
    }

    It 'maps colon : -> shift+; (2a 27 / a7 aa)' {
        $r = Convert-CharToScancode -Char ':'
        $r.Press   | Should -Be '2a 27'
        $r.Release | Should -Be 'a7 aa'
    }

    It 'maps dash - -> 0c/8c' {
        $r = Convert-CharToScancode -Char '-'
        $r.Press   | Should -Be '0c'
        $r.Release | Should -Be '8c'
    }

    It 'maps underscore _ -> shift+- (2a 0c / 8c aa)' {
        $r = Convert-CharToScancode -Char '_'
        $r.Press   | Should -Be '2a 0c'
        $r.Release | Should -Be '8c aa'
    }

    It 'throws on unsupported character (TAB)' {
        { Convert-CharToScancode -Char "`t" } | Should -Throw
    }
}

Describe 'ConvertTo-ScancodeSequence -- full strings' {

    It 'encodes "abc" as press/release pairs interleaved' {
        $seq = ConvertTo-ScancodeSequence -Text 'abc'
        $seq | Should -Be '1e 9e 30 b0 2e ae'
    }

    It 'encodes a known kickstart fragment' {
        # "ip=1.2.3.4"
        $seq = ConvertTo-ScancodeSequence -Text 'ip=1.2.3.4'
        $expected = '17 97 19 99 0d 8d 02 82 34 b4 03 83 34 b4 04 84 34 b4 05 85'
        $seq | Should -Be $expected
    }

    It 'encodes "Aa" using shift correctly' {
        # A = 2a 1e / 9e aa, a = 1e / 9e
        $seq = ConvertTo-ScancodeSequence -Text 'Aa'
        $seq | Should -Be '2a 1e 9e aa 1e 9e'
    }

    It 'roundtrips the boot params line head (just the prefix)' {
        # Start of: " inst.ks=http://"
        $seq = ConvertTo-ScancodeSequence -Text ' inst.ks=http://'
        # space=39 b9, i=17 97, n=31 b1, s=1f 9f, t=14 94, .=34 b4, k=25 a5, s=1f 9f
        # ==0d 8d, h=23 a3, t=14 94, t=14 94, p=19 99, :=2a 27 / a7 aa, /=35 b5, /=35 b5
        $expected = '39 b9 17 97 31 b1 1f 9f 14 94 34 b4 25 a5 1f 9f 0d 8d 23 a3 14 94 14 94 19 99 2a 27 a7 aa 35 b5 35 b5'
        $seq | Should -Be $expected
    }
}

Describe 'ConvertTo-SpecialKeyScancode -- named keys' {

    It 'Enter -> "1c 9c"' {
        ConvertTo-SpecialKeyScancode -Key 'Enter' | Should -Be '1c 9c'
    }

    It 'Tab -> "0f 8f"' {
        ConvertTo-SpecialKeyScancode -Key 'Tab' | Should -Be '0f 8f'
    }

    It 'CtrlX -> "1d 2d ad 9d" (Ctrl + X)' {
        ConvertTo-SpecialKeyScancode -Key 'CtrlX' | Should -Be '1d 2d ad 9d'
    }

    It 'Esc -> "01 81"' {
        ConvertTo-SpecialKeyScancode -Key 'Esc' | Should -Be '01 81'
    }

    It 'throws on unknown key' {
        { ConvertTo-SpecialKeyScancode -Key 'F13' } | Should -Throw
    }
}
