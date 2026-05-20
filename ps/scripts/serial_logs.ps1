param(
    [string]$Port = "",
    [int]$Baud = 115200
)

if ([string]::IsNullOrWhiteSpace($Port)) {
    Write-Host "Usage: make logs PORT=COMx"
    exit 2
}

$serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    $Baud,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)

$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.ReadTimeout = 200
$serial.NewLine = "`n"
$serial.DtrEnable = $false
$serial.RtsEnable = $false

try {
    $serial.Open()
    Write-Host "Streaming $Port at $Baud baud. Press Ctrl+C to stop."

    while ($true) {
        try {
            $line = $serial.ReadLine()
            Write-Output $line.TrimEnd("`r")
        } catch [System.TimeoutException] {
        }
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
