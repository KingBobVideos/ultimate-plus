from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib,json,shutil,sys
root=Path(__file__).resolve().parent.parent
sd=root.parent/'Ultimate Mod Lab/Emulator/Eden/user/sdmc'
release=root/'releases'/sys.argv[1]
release.mkdir(exist_ok=True)
package=release
release=package/'Data'
release.mkdir(exist_ok=True)
folders=['ultimate/mods','ultimate/config','ultimate/arcropolis/config','ultimate/arcropolis/resources','atmosphere/contents/01006A800016E000']
files=[]; parts=[]; archive=None; size=0
existing={}
for old in sorted(release.glob('UltimatePlus-*.zip')):
 try:
  with ZipFile(old) as z:
   for info in z.infolist():existing[info.filename]=info.file_size
 except Exception:
  if old!=sorted(release.glob('UltimatePlus-*.zip'))[-1]:raise
  old.rename(old.with_suffix('.partial'))
  continue
 parts.append(old.name)
try:
 for folder in folders:
  assert (sd/folder).is_dir(),folder
  for path in sorted((sd/folder).rglob('*')):
   if not path.is_file():continue
   if path.is_symlink():raise ValueError(path)
   n=path.stat().st_size
   rel=path.relative_to(sd).as_posix()
   if rel in existing:
    with path.open('rb') as inp:files.append((rel,n,hashlib.file_digest(inp,'sha256').hexdigest()))
    continue
   if archive is None or size+n>1_500_000_000:
    if archive:archive.close()
    name=f'UltimatePlus-{len(parts)+1:02}.zip';parts.append(name)
    archive=ZipFile(release/name,'x',ZIP_DEFLATED,compresslevel=1);size=0
   rel=path.relative_to(sd).as_posix()
   with path.open('rb') as inp,archive.open(rel,'w',force_zip64=True) as out:
    h=hashlib.sha256()
    while block:=inp.read(1048576):out.write(block);h.update(block)
   files.append((rel,n,h.hexdigest()));size+=n
finally:
 if archive:archive.close()
# Read every archived byte back and compare it with the source digest.
expected={p:(n,h) for p,n,h in files}
for name in parts:
 with ZipFile(release/name) as z:
  for info in z.infolist():
   n,h=expected.pop(info.filename)
   with z.open(info) as f: assert n==info.file_size and hashlib.file_digest(f,'sha256').hexdigest()==h
assert not expected
(release/'parts.sha256').write_text(''.join(hashlib.file_digest((release/name).open('rb'),'sha256').hexdigest()+'  '+name+'\n' for name in parts))
(root/'manifest'/(package.name+'.json')).write_text(json.dumps(dict(smash='13.0.5',files=files),separators=(',',':')))
shutil.copy2(root/'installer/Install.ps1',release/'Install.ps1')
shutil.copy2(root/'installer/Install.cmd',package/'Play Ultimate+.cmd')
print(len(files),len(parts),sum(n for _,n,_ in files),flush=True)


eden=sd.parent.parent
portable=release/'Eden'
(portable/'user/sdmc').mkdir(parents=True,exist_ok=True)
for item in ['eden.exe','LICENSE.txt','README.md']:
 shutil.copy2(eden/item,portable/item)
shutil.copytree(eden/'LICENSES',portable/'LICENSES',dirs_exist_ok=True)