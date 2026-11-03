// class_checksum — checksum and size ROOT computes for a candidate class layout.
// usage: dsw macro --clean-room class_checksum <decl.h> <fully::qualified::Class>
// <decl.h> declares the struct under its exact namespace, member names and types, e.g.
//   namespace a::b { struct C { uint64_t t; uint8_t type; }; }
// Use --clean-room so no experiment dictionary already defines the class. Use one call
// per candidate layout (a name can be declared only once per process). The layout whose
// checksum equals the one stored in a file (streamer_cmp) is the one the file was
// written with.
#include <TClass.h>
#include <TInterpreter.h>
#include <TSystem.h>
#include <cstdio>
#include <fstream>
#include <sstream>

void class_checksum(const char* declfile, const char* fqn) {
  std::ifstream in(declfile);
  if (!in) { printf("cannot read %s\n", declfile); gSystem->Exit(1); }
  std::stringstream ss; ss << in.rdbuf();
  // load=true: let ROOT autoload a dictionary if one is reachable, which is exactly
  // what must not happen here
  if (TClass* pre = TClass::GetClass(fqn, true, true); pre && pre->HasDictionary()) {
    printf("ERROR: %s already has a dictionary (checksum=%u); the declaration would be "
           "ignored. Use --clean-room.\n", fqn, pre->GetCheckSum());
    gSystem->Exit(1);
  }
  if (!gInterpreter->Declare(ss.str().c_str())) { printf("declaration failed\n"); gSystem->Exit(1); }
  TClass* c = TClass::GetClass(fqn);
  if (!c) { printf("no class %s after the declaration\n", fqn); gSystem->Exit(1); }
  printf("%s: checksum=%u size=%d\n", fqn, c->GetCheckSum(), c->Size());
}
