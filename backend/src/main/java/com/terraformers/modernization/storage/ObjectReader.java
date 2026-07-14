package com.terraformers.modernization.storage;

public interface ObjectReader {

    ObjectMetadata readMetadata(ObjectReference reference);

    ObjectContent readContent(ObjectReference reference);
}
