package com.terraformers.modernization.reference;

import java.util.List;

public interface ReferenceRetriever {

    List<ReferenceDocument> retrieve(ReferenceQuery query);
}
