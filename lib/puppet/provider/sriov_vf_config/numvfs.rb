Puppet::Type.type(:sriov_vf_config).provide(:numvfs) do
  desc <<-EOT
    The file /sys/class/net/<sriov_interface_name>/device/sriov_numvfs will be
    present when a physical PCIe device supports SR-IOV. A number written to
    this file will enable the specified number of VFs. This provider shall read
    the file and ensure that the value is zero, before writing the number of
    VFs that should be enabled. If the VFs needs to be disabled then we shall
    write a zero to this file.
  EOT

  def create
    if File.file?(sriov_numvfs_path)
      _set_numvfs
      _apply_hw_offload
    else
      warning("#{sriov_numvfs_path} doesn't exist. Check if #{sriov_get_interface} is a valid network interface supporting SR-IOV")
    end
  end

  def destroy
    if File.file?(sriov_numvfs_path)
      File.write(sriov_numvfs_path,"0")
    end
  end

  def exists?
    if File.file?(sriov_numvfs_path)
      cur_value = File.read(sriov_numvfs_path)
      if cur_value.to_i == sriov_numvfs_value
        return true
      end
    end
    return false
  end

  def _set_numvfs
    # During an update, the content of file sriov_numvfs_path has to be set
    # to 0 (ZERO), before writing the actual value
    cur_value = File.read(sriov_numvfs_path)
    if cur_value != 0
      File.write(sriov_numvfs_path,"0")
    end
    File.write(sriov_numvfs_path,sriov_numvfs_value)
  end

  def _apply_hw_offload
    # Changing the mode of virtual functions to hw-offload
    if ovs_mode == "switchdev"
      cur_value = File.read(vendor_path).strip
      if cur_value == "0x15b3"
        vfs_pcis = get_vfs_pcis
        # Unbinding virtual functions
        vfs_pcis.each do|vfs_pci|
          File.write("/sys/bus/pci/drivers/mlx5_core/unbind",vfs_pci)
        end
      end
      # Changing the mode of sriov interface to switchdev mode
      %x{devlink dev eswitch set pci/#{get_interface_pci} mode switchdev}
      %x{ethtool -K #{sriov_get_interface} hw-tc-offload on}
      if get_interface_device == "0x1013" || get_interface_device == "0x1015"
        %x{devlink dev eswitch set pci/#{get_interface_pci} inline-mode transport}
      end
      if cur_value == "0x15b3"
        # Binding virtual functions
        vfs_pcis.each do|vfs_pci|
          File.write("/sys/bus/pci/drivers/mlx5_core/bind",vfs_pci)
        end
      end
    end
  end

  def sriov_numvfs_path
    "/sys/class/net/#{sriov_get_interface}/device/sriov_numvfs"
  end

  def sriov_get_interface
    resource[:name].split(':', 3).first
  end

  def sriov_numvfs_value
    resource[:name].split(':', 3)[1].to_i
  end

  def vendor_path
    "/sys/class/net/#{sriov_get_interface}/device/vendor"
  end

  def ovs_mode
    if resource[:name].split(':', 3).length == 2
      'legacy'
    else
      resource[:name].split(':', 3).last
    end
  end

  def get_vfs_pcis
    %x{cat /sys/class/net/#{sriov_get_interface}/device/virtfn*/uevent | grep PCI_SLOT_NAME | cut -d'=' -f2}.split(/\n+/)
  end

  def get_interface_pci
    %x{ethtool -i #{sriov_get_interface} | grep bus-info | awk {'print$2'}}.strip
  end

  def get_interface_device
    %x{cat /sys/class/net/#{sriov_get_interface}/device/device}.strip
  end
end
