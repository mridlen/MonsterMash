###############################################################################
### ASSEMBLY IMPORTS
###############################################################################

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

###############################################################################
### PATH RESOLUTION
###############################################################################

$script:scriptRoot = $PSScriptRoot
$script:unwadExe   = Join-Path $script:scriptRoot "unwad.exe"

###############################################################################
### VERIFY UNWAD.EXE EXISTS
###############################################################################

if (-not (Test-Path $script:unwadExe)) {
    [System.Windows.MessageBox]::Show(
        "unwad.exe not found at:`n$script:unwadExe`n`nPlease place unwad.exe in the same directory as this script.",
        "Missing Executable",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

###############################################################################
### XAML LAYOUT
###############################################################################

[xml]$script:xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Unwad V2 -- Monster Mash WAD Processor"
    Width="720" Height="700"
    MinWidth="500" MinHeight="550"
    WindowStartupLocation="CenterScreen">

    <Window.Resources>
        <Style x:Key="SliderLabelStyle" TargetType="Label">
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Width" Value="70"/>
        </Style>
        <Style x:Key="SliderValueStyle" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="TextAlignment" Value="Right"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Width" Value="45"/>
            <Setter Property="Margin" Value="4,0,0,0"/>
        </Style>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <!-- Row 0: Folder buttons -->
            <RowDefinition Height="Auto"/>
            <!-- Row 1: Slider defaults group box -->
            <RowDefinition Height="Auto"/>
            <!-- Row 2: Options row -->
            <RowDefinition Height="Auto"/>
            <!-- Row 3: Action buttons -->
            <RowDefinition Height="Auto"/>
            <!-- Row 4: Output label -->
            <RowDefinition Height="Auto"/>
            <!-- Row 5: Output text box (fills remaining space) -->
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- ============================================================ -->
        <!-- ROW 0: Folder Buttons -->
        <!-- ============================================================ -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <Button x:Name="btnSource" Content="Open Source Folder"
                    Padding="12,6" Margin="0,0,8,0"/>
            <Button x:Name="btnIWADs" Content="Open IWADs Folder"
                    Padding="12,6"/>
        </StackPanel>

        <!-- ============================================================ -->
        <!-- ROW 1: Slider Defaults GroupBox -->
        <!-- ============================================================ -->
        <GroupBox Grid.Row="1" Header="Slider Defaults" Margin="0,0,0,8" Padding="8">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Weapon Slider -->
                <DockPanel Grid.Row="0" Margin="0,4,0,4">
                    <Label Style="{StaticResource SliderLabelStyle}" Content="Weapon"/>
                    <TextBlock x:Name="lblWeapon" Style="{StaticResource SliderValueStyle}"
                               Text="0.00" DockPanel.Dock="Right"/>
                    <Slider x:Name="sliderWeapon"
                            Minimum="0" Maximum="20" Value="0"
                            TickFrequency="0.02" IsSnapToTickEnabled="True"
                            VerticalAlignment="Center"/>
                </DockPanel>

                <!-- Monster Slider -->
                <DockPanel Grid.Row="1" Margin="0,4,0,4">
                    <Label Style="{StaticResource SliderLabelStyle}" Content="Monster"/>
                    <TextBlock x:Name="lblMonster" Style="{StaticResource SliderValueStyle}"
                               Text="1.00" DockPanel.Dock="Right"/>
                    <Slider x:Name="sliderMonster"
                            Minimum="0" Maximum="20" Value="1"
                            TickFrequency="0.02" IsSnapToTickEnabled="True"
                            VerticalAlignment="Center"/>
                </DockPanel>

                <!-- Ally Slider -->
                <DockPanel Grid.Row="2" Margin="0,4,0,4">
                    <Label Style="{StaticResource SliderLabelStyle}" Content="Ally"/>
                    <TextBlock x:Name="lblAlly" Style="{StaticResource SliderValueStyle}"
                               Text="1.00" DockPanel.Dock="Right"/>
                    <Slider x:Name="sliderAlly"
                            Minimum="0" Maximum="20" Value="1"
                            TickFrequency="0.02" IsSnapToTickEnabled="True"
                            VerticalAlignment="Center"/>
                </DockPanel>

                <!-- Ammo Slider -->
                <DockPanel Grid.Row="3" Margin="0,4,0,4">
                    <Label Style="{StaticResource SliderLabelStyle}" Content="Ammo"/>
                    <TextBlock x:Name="lblAmmo" Style="{StaticResource SliderValueStyle}"
                               Text="10.00" DockPanel.Dock="Right"/>
                    <Slider x:Name="sliderAmmo"
                            Minimum="0" Maximum="20" Value="10"
                            TickFrequency="0.02" IsSnapToTickEnabled="True"
                            VerticalAlignment="Center"/>
                </DockPanel>

                <!-- Nice Item Slider -->
                <DockPanel Grid.Row="4" Margin="0,4,0,4">
                    <Label Style="{StaticResource SliderLabelStyle}" Content="Nice Item"/>
                    <TextBlock x:Name="lblNiceItem" Style="{StaticResource SliderValueStyle}"
                               Text="0.30" DockPanel.Dock="Right"/>
                    <Slider x:Name="sliderNiceItem"
                            Minimum="0" Maximum="20" Value="0.3"
                            TickFrequency="0.02" IsSnapToTickEnabled="True"
                            VerticalAlignment="Center"/>
                </DockPanel>

                <!-- Pickup Slider -->
                <DockPanel Grid.Row="5" Margin="0,4,0,4">
                    <Label Style="{StaticResource SliderLabelStyle}" Content="Pickup"/>
                    <TextBlock x:Name="lblPickup" Style="{StaticResource SliderValueStyle}"
                               Text="0.30" DockPanel.Dock="Right"/>
                    <Slider x:Name="sliderPickup"
                            Minimum="0" Maximum="20" Value="0.3"
                            TickFrequency="0.02" IsSnapToTickEnabled="True"
                            VerticalAlignment="Center"/>
                </DockPanel>

            </Grid>
        </GroupBox>

        <!-- ============================================================ -->
        <!-- ROW 2: Options Row -->
        <!-- ============================================================ -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,8"
                    VerticalAlignment="Center">
            <CheckBox x:Name="chkSkipCleanup" Content="Skip post-run cleanup"
                      VerticalAlignment="Center" Margin="0,0,16,0"/>
            <Label Content="Verbosity" VerticalAlignment="Center" Margin="0,0,4,0"/>
            <ComboBox x:Name="cmbVerbosity" SelectedIndex="0"
                      VerticalAlignment="Center" Width="120">
                <ComboBoxItem Content="Errors only"/>
                <ComboBoxItem Content="Warnings"/>
                <ComboBoxItem Content="Info"/>
                <ComboBoxItem Content="Debug"/>
            </ComboBox>
        </StackPanel>

        <!-- ============================================================ -->
        <!-- ROW 3: Action Buttons -->
        <!-- ============================================================ -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,0,0,8">
            <Button x:Name="btnRun" Content="Run Unwad"
                    Padding="16,8" Margin="0,0,8,0"
                    FontWeight="Bold"
                    Background="#0078D4"
                    Foreground="White"/>
            <Button x:Name="btnClean" Content="Clean Only"
                    Padding="16,8"/>
        </StackPanel>

        <!-- ============================================================ -->
        <!-- ROW 4: Output Label -->
        <!-- ============================================================ -->
        <TextBlock Grid.Row="4" Text="Output" Margin="0,0,0,4"
                   FontWeight="SemiBold"/>

        <!-- ============================================================ -->
        <!-- ROW 5: Output TextBox -->
        <!-- ============================================================ -->
        <TextBox x:Name="txtOutput"
                 Grid.Row="5"
                 IsReadOnly="True"
                 FontFamily="Consolas"
                 FontSize="12"
                 TextWrapping="Wrap"
                 VerticalScrollBarVisibility="Auto"
                 AcceptsReturn="True"
                 VerticalAlignment="Stretch"
                 HorizontalAlignment="Stretch"/>

    </Grid>
</Window>
"@

###############################################################################
### CREATE WINDOW AND GET WIDGET REFERENCES
###############################################################################

# Build the window from XAML
$script:reader = New-Object System.Xml.XmlNodeReader $script:xaml
$script:window = [Windows.Markup.XamlReader]::Load($script:reader)

# -- Buttons --
$script:btnSource = $script:window.FindName("btnSource")
$script:btnIWADs  = $script:window.FindName("btnIWADs")
$script:btnRun    = $script:window.FindName("btnRun")
$script:btnClean  = $script:window.FindName("btnClean")

# -- Sliders --
$script:sliderWeapon   = $script:window.FindName("sliderWeapon")
$script:sliderMonster  = $script:window.FindName("sliderMonster")
$script:sliderAlly     = $script:window.FindName("sliderAlly")
$script:sliderAmmo     = $script:window.FindName("sliderAmmo")
$script:sliderNiceItem = $script:window.FindName("sliderNiceItem")
$script:sliderPickup   = $script:window.FindName("sliderPickup")

# -- Slider value labels --
$script:lblWeapon   = $script:window.FindName("lblWeapon")
$script:lblMonster  = $script:window.FindName("lblMonster")
$script:lblAlly     = $script:window.FindName("lblAlly")
$script:lblAmmo     = $script:window.FindName("lblAmmo")
$script:lblNiceItem = $script:window.FindName("lblNiceItem")
$script:lblPickup   = $script:window.FindName("lblPickup")

# -- Other controls --
$script:chkSkipCleanup = $script:window.FindName("chkSkipCleanup")
$script:cmbVerbosity   = $script:window.FindName("cmbVerbosity")
$script:txtOutput      = $script:window.FindName("txtOutput")

###############################################################################
### SHOW WINDOW
###############################################################################

[void]$script:window.ShowDialog()
