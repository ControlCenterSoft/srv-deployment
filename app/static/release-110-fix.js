/* Control Center 1.0.10 notification/UI cleanup */
const dhcpBefore110Fix=dhcp;
dhcp=async function(){
  await dhcpBefore110Fix();
  /* Persistent service/apply state is represented by status badges and bell events. */
  if($('#dhcpMessage')) $('#dhcpMessage').textContent='';
};

const refreshDhcpBefore110Fix=refreshDhcpRuntime;
refreshDhcpRuntime=async function(){
  await refreshDhcpBefore110Fix();
  if($('#dhcpMessage')) $('#dhcpMessage').textContent='';
};

const settingsBefore110Fix=settings;
settings=async function(){
  await settingsBefore110Fix();
  try{
    const w=await api('/api/settings/web');
    syncWeb110(w);
  }catch(e){console.error(e);}
};
