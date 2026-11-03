// dsw_ls.C — list the contents of a ROOT file (replacement for the broken rootls).
// usage: root -l -b -q 'dsw_ls.C("file.root")'
#include <TFile.h>
#include <TDirectory.h>
#include <TKey.h>
#include <TTree.h>
#include <TClass.h>
#include <TString.h>
#include <TSystem.h>
#include <iostream>

static void dsw_ls_dir(TDirectory* dir, const TString& prefix) {
  TIter next(dir->GetListOfKeys());
  while (TKey* key = static_cast<TKey*>(next())) {
    TString path = prefix + key->GetName();
    TClass* cl = TClass::GetClass(key->GetClassName());
    std::cout << path << ";" << key->GetCycle() << "  [" << key->GetClassName() << "]";
    if (cl && cl->InheritsFrom(TTree::Class())) {
      TTree* t = static_cast<TTree*>(key->ReadObj());
      std::cout << "  entries=" << t->GetEntries()
                << " branches=" << t->GetListOfBranches()->GetEntries();
    }
    std::cout << "\n";
    if (cl && cl->InheritsFrom(TDirectory::Class())) {
      dsw_ls_dir(static_cast<TDirectory*>(key->ReadObj()), path + "/");
    }
  }
}

void dsw_ls(const char* fname) {
  TFile* f = TFile::Open(fname, "READ");
  if (!f || f->IsZombie()) {
    std::cerr << "dsw_ls: cannot open " << fname << "\n";
    gSystem->Exit(1);
  }
  dsw_ls_dir(f, "");
  f->Close();
}
