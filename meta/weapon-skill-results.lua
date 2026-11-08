local meta={
    types={[185]='damage',[187]='hp_drain',[197]='damage',[225]='mp_drain',
        [264]='damage',[747]='damage',[748]='hp_drain',[750]='mp_drain'},
    skillchains={}
}
local names={'Light','Darkness','Gravitation','Fragmentation','Distortion','Fusion',
    'Compression','Liquefaction','Induration','Reverberation','Transfixion','Scission','Detonation','Impaction'}
for i,name in ipairs(names) do
    meta.skillchains[287+i]={name=name,damage=true}
    meta.skillchains[384+i]={name=name,absorbed=true}
end
meta.skillchains[767]={name='Radiance',damage=true}
meta.skillchains[768]={name='Umbra',damage=true}
meta.skillchains[769]={name='Radiance',absorbed=true}
meta.skillchains[770]={name='Umbra',absorbed=true}
return meta
