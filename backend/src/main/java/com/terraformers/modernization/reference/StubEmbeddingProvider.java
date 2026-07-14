package com.terraformers.modernization.reference;

import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnMissingBean(EmbeddingProvider.class)
public class StubEmbeddingProvider implements EmbeddingProvider {

    @Override
    public List<Float> embed(String text) {
        return List.of(0.12f, 0.34f, 0.56f, 0.78f);
    }
}
