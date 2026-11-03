// streamer_cmp — compare a class's layout as stored in a file with the dictionary loaded now.
// usage: dsw macro streamer_cmp <file.root> <fully::qualified::Class>
// Run in the normal (dunesw) environment so the runtime dictionary is the one lar uses.
// Red flags: same checksum but different element lists (a stale pinned checksum);
// offsets/types that don't match the header; runtime size != sizeof in the header.
#include <TFile.h>
#include <TClass.h>
#include <TList.h>
#include <TVirtualStreamerInfo.h>
#include <TString.h>
#include <TSystem.h>
#include <cstdio>

void streamer_cmp(const char* fname, const char* fqn) {
  TFile* f = TFile::Open(fname, "READ");
  if (!f || f->IsZombie()) { printf("cannot open %s\n", fname); gSystem->Exit(1); }
  int nfile = 0;
  for (TObject* obj : *f->GetStreamerInfoList()) {
    auto* si = dynamic_cast<TVirtualStreamerInfo*>(obj);
    if (!si || !TString(si->GetName()).EqualTo(fqn)) continue;
    ++nfile;
    printf("=== FILE    version=%d checksum=%u\n", si->GetClassVersion(), si->GetCheckSum());
    si->ls();
  }
  if (!nfile) printf("=== FILE    no streamer info for %s in %s\n", fqn, fname);
  TClass* c = TClass::GetClass(fqn);
  if (!c) { printf("=== RUNTIME no dictionary for %s\n", fqn); return; }
  printf("=== RUNTIME version=%d checksum=%u size=%d hasDictionary=%d\n",
         c->GetClassVersion(), c->GetCheckSum(), c->Size(), (int)c->HasDictionary());
  if (c->GetStreamerInfo()) c->GetStreamerInfo()->ls();
}
