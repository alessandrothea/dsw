// tree_scan — entry count, branch list and the first rows of a tree (e.g. TFileService output).
// usage: dsw macro tree_scan <file.root> <dir/tree> [branches="*"] [nrows=10]
//   branches: TTree::Scan selection, e.g. "event:adc_integral:channel_start"
#include <TFile.h>
#include <TTree.h>
#include <TBranch.h>
#include <TLeaf.h>
#include <TSystem.h>
#include <cstdio>
#include <cstdlib>

void tree_scan(const char* fname, const char* tpath, const char* branches = "*",
               const char* nrows = "10") {
  TFile* f = TFile::Open(fname, "READ");
  if (!f || f->IsZombie()) { printf("cannot open %s\n", fname); gSystem->Exit(1); }
  TTree* t = nullptr;
  f->GetObject(tpath, t);
  if (!t) { printf("no tree %s in %s (list with: dsw ls %s)\n", tpath, fname, fname); gSystem->Exit(1); }
  printf("%s: entries=%lld\n", tpath, t->GetEntries());
  for (TObject* o : *t->GetListOfBranches()) {
    auto* b = static_cast<TBranch*>(o);
    TLeaf* l = static_cast<TLeaf*>(b->GetListOfLeaves()->First());
    printf("  %-32s %s\n", b->GetName(), l ? l->GetTypeName() : b->GetClassName());
  }
  t->Scan(branches, "", "colsize=14", std::atoll(nrows));
}
