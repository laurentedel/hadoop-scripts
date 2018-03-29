def list_regions(table_name, region_server_name = "")
  admin = @hbase.admin(@hbase)
  admin_instance = admin.instance_variable_get("@admin")
  conn_instance = admin_instance.getConnection()
  cluster_status = admin_instance.getClusterStatus()
  hregion_locator_instance = conn_instance.getRegionLocator(TableName.valueOf(table_name))
  hregion_locator_list = hregion_locator_instance.getAllRegionLocations()

  table_max_file_size = (admin_instance.getTableDescriptor(TableName.valueOf(table_name)).getMaxFileSize()/1024/1024).ceil
  if table_max_file_size < 0
    table_max_file_size = (admin_instance.getConfiguration.getLong("hbase.hregion.max.filesize", 5)/1024/1024).ceil
  end
  results = Array.new

  begin
    hregion_locator_list.each do |hregion|
      hregion_info = hregion.getRegionInfo()
      server_name = hregion.getServerName()
      if hregion.getServerName().toString.start_with? region_server_name
        startKey = Bytes.toString(hregion.getRegionInfo().getStartKey())
        endKey = Bytes.toString(hregion.getRegionInfo().getEndKey())
        region_load_map = cluster_status.getLoad(server_name).getRegionsLoad()
        region_load = region_load_map.get(hregion_info.getRegionName())
        region_store_file_size = region_load.getStorefileSizeMB()
        occupancy = (region_store_file_size*100/table_max_file_size).ceil
        region_requests = region_load.getRequestsCount()
        results << { "server" => hregion.getServerName().toString(), "name" => hregion_info.getRegionNameAsString(), "startkey" => startKey, "endkey" => endKey, "size" => region_store_file_size, "occupancy" => occupancy, "requests" => region_requests }
      end
    end
  ensure
    hregion_locator_instance.close()
  end

  @end_time = Time.now

  printf("%-60s | %-60s | %-15s | %-15s | %-15s | %-15s | %-15s", "SERVER_NAME", "REGION_NAME", "START_KEY", "END_KEY", "SIZE(MB)", "OCCUPANCY(%)", "REQ");
  printf("\n")
  for result in results
    printf("%-60s | %-60s | %-15s | %-15s | %-15s | %-15s | %-15s", result["server"], result["name"], result["startkey"], result["endkey"], result["size"], result["occupancy"], result["requests"]);
      printf("\n")
  end
  printf("%d rows", results.size)

end
