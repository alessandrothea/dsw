// read_all — null test: read every entry of a tree with plain ROOT, no art/analyzer code.
// usage: dsw macro read_all <file.root> [tree=Events]
// If this crashes, the file or the dictionary is broken, not your module. Output is
// flushed after every entry so the last good entry survives an abort.
#include <TFile.h>
#include <TTree.h>
#include <TSystem.h>
#include <cstdio>

void read_all(const char* fname, const char* tname = "Events") {
  TFile* f = TFile::Open(fname, "READ");
  if (!f || f->IsZombie()) { printf("cannot open %s\n", fname); gSystem->Exit(1); }
  TTree* t = nullptr;
  f->GetObject(tname, t);
  if (!t) { printf("no tree %s in %s\n", tname, fname); gSystem->Exit(1); }
  printf("%s: %lld entries\n", tname, t->GetEntries()); fflush(stdout);
  for (Long64_t i = 0; i < t->GetEntries(); ++i) {
    int nb = t->GetEntry(i);
    printf("entry %lld ok (%d bytes)\n", i, nb); fflush(stdout);
  }
  printf("ALL OK\n");
}
