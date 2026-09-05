# Windows firmware-change reboot runbook

Status: `PLANNED`. The user performs and controls the reboot. Automation must not reboot Windows.

## Purpose

Use one maintenance reboot to:

1. Enable AMD CPU virtualization (`SVM` or the motherboard's equivalent label) so WSL 2 and Docker can run.
2. Enable the memory kit's vendor profile (`DOCP`) so RAM operates at its intended profile rather than the current reduced setting.

Do not combine this maintenance window with BIOS flashing, operating-system updates, driver updates, storage-mode changes, Secure Boot changes, CPU overclocking, or manual voltage/timing tuning.

The machine has recent processor/cache WHEA errors. They do not prove a memory fault, but they make it unsafe to stack DOCP with CPU, curve-optimizer, fabric-clock, or voltage tuning. The first boot is therefore a controlled stability baseline, not proof that DDR4-3600 is stable.

## Safe prerequisites before reboot

- Commit and push the latest sanitized Windows handoff, then verify the remote commit.
- Save work and stop model downloads, conversions, containers, virtual machines, and other disk-writing workloads.
- Confirm the Docker engine is stopped before firmware maintenance.
- Check whether device encryption or BitLocker is active and ensure the recovery key is accessible through the user's trusted recovery method. Do not record the key in this repository.
- Record the current firmware settings privately or photograph the relevant pages for rollback.
- Confirm there is no pending firmware or operating-system update that would make this reboot perform unrelated changes.
- Keep the system on stable power.
- Confirm the Windows Subsystem for Linux and Virtual Machine Platform features are enabled and `hypervisorlaunchtype` is `Auto`.
- Temporarily disable only the AI Suite and DIP Away Mode logon tasks for the first stability boot. Leave fan-control services enabled.

## Firmware changes during the user-controlled reboot

1. Restart manually and press `Delete` or `F2` during POST.
2. Press `F7` to enter Advanced Mode.
3. Photograph the current boot, fan, CPU-tuning, and memory pages for private rollback reference.
4. Neutralize stacked CPU tuning: leave CPU Core Ratio, BCLK, Precision Boost Overdrive, Curve Optimizer, SOC voltage, and FCLK at `Auto`/default. Do not enable TPU.
5. Open `Advanced > CPU Configuration > SVM Mode` and set it to `Enabled`.
6. Open `Ai Tweaker > Ai Overclock Tuner`, select `D.O.C.P.`, and select the kit profile.
7. Confirm the profile reports approximately DDR4-3600, 16-19-19-39, and 1.35 V. Do not enter those values manually.
8. Preserve Secure Boot and fTPM. Do not clear fTPM, change CSM or storage-controller mode, or enable IOMMU unnecessarily.
9. Press `F10`, inspect the change summary, and save once.

Memory training can produce a blank display and multiple automatic restarts. Wait at least five minutes before intervening.

### If the machine does not POST

Allow the board's automatic failed-training recovery to finish; do not interrupt it with repeated blind power cycles. If there is still no display or POST after the five-minute wait:

1. Hold the power button to turn the machine off, switch off or disconnect stable input power, and follow the motherboard manual's documented Clear CMOS/recovery procedure exactly.
2. Do not let automation attempt firmware recovery, pin shorting, or power cycling.
3. Expect firmware settings to return to defaults. Re-enter UEFI and restore only the known boot, fan, Secure Boot, fTPM, and storage-controller settings needed for the prior Windows installation. Do not clear fTPM.
4. Keep the trusted device-encryption recovery method available; never record its recovery key in this repository.
5. Leave DOCP disabled for the recovery boot, but re-enable SVM if the reset disabled it. Report the recovery state before attempting memory tuning again.

## First Windows boot verification

Run these checks before starting the Docker rebuild:

```powershell
Get-CimInstance Win32_Processor |
    Select-Object Name, VirtualizationFirmwareEnabled, VMMonitorModeExtensions

Get-CimInstance Win32_PhysicalMemory |
    Select-Object Manufacturer, Capacity, Speed, ConfiguredClockSpeed

wsl --status
wsl --list --verbose

nvidia-smi
```

Then:

1. Confirm `VirtualizationFirmwareEnabled` is true.
2. Confirm the configured memory clock matches the selected profile as reported by Windows. Account for tools that report the physical clock rather than the effective DDR transfer rate.
3. Inspect the Windows System event log for new WHEA hardware errors before and during a short stability workload.
4. Start Docker Desktop manually and verify the engine responds before enabling startup behavior or deploying workloads.
5. Confirm GPU visibility from Windows. Confirm it from a disposable GPU container only after the Docker data location and clean rebuild are complete.
6. Update `state/windows/STATUS.md` with sanitized results; never paste raw inventories.

## Success criteria

- Firmware virtualization is reported enabled.
- WSL 2 can start without a virtualization-disabled error.
- Docker's Linux engine starts from the approved regular-storage data location.
- Memory is reported at the selected rated profile and passes a stability check without new WHEA errors.
- The NVIDIA driver remains operational.
- No new WHEA errors appear during the initial memory and CPU stability workload.

## Rollback and failure handling

- If DDR4-3600 fails to train, boot, or test without new WHEA errors, return to firmware setup, keep DOCP selected, and override only Memory Frequency to DDR4-3200. Keep FCLK and CPU/SOC controls on `Auto`.
- If errors continue at DDR4-3200, disable DOCP entirely and diagnose CPU/PBO/Curve Optimizer or hardware separately. Keep virtualization enabled if it is not implicated.
- Do not raise DRAM or memory-controller voltage as an automated workaround.
- If virtualization still reports disabled, re-enter firmware and verify both the CPU virtualization setting and the Windows virtualization feature prerequisites. Do not factory-reset firmware.
- If device encryption requests recovery, use the user's trusted recovery method and do not disclose or store the key in project files.
- Any additional reboot remains user-controlled and requires an updated handoff.

## Firmware update policy

The installed firmware already exposes both required settings. A BIOS flash is not required and is explicitly excluded from this reboot. Firmware updating is separate maintenance because it resets settings, can invoke device-encryption recovery, and adds failure modes unrelated to bringing up Docker.

## References

- [ASUS BIOS manual](https://dlcdnets.asus.com/pub/ASUS/mb/SocketAM4/ROG_STRIX_B550-I_GAMING/E17670_ROG_STRIX_B550-I_BIOS_manual_EM_WEB.pdf)
- [G.Skill memory-kit specification](https://www.gskill.com/tw/specification/203/327/1562840211/F4-3600C16D-32GTZNC-Specification)
- [AMD Ryzen 9 5900X specification](https://www.amd.com/en/products/processors/desktops/ryzen/5000-series/amd-ryzen-9-5900x.html)
- [Microsoft virtualization guidance](https://support.microsoft.com/en-US/Windows/Experience/enable-virtualization-on-windows)
