/// Injectable FRB `lemmaKeysForSurfaces` seam (Vocab add, stub→morph migration,
/// later Reader). Default production impl = generated FRB.
typedef LemmaKeysForSurfacesFn =
    Future<List<String>> Function(List<String> surfaces);
