package com.terraformers.modernization.reference;

import java.util.List;

public interface EmbeddingProvider {

    List<Float> embed(String text);
}
