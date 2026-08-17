# Native Mojo value types shared across the crawler/extraction/db layers.


struct Product(Copyable, Movable):
    var url: String
    var name: String
    var price: Optional[Float64]
    var currency: String
    var image_url: String
    var category: String
    var description: String
    var source_listing_url: String

    def __init__(
        out self,
        url: String,
        name: String,
        price: Optional[Float64] = None,
        currency: String = String(""),
        image_url: String = String(""),
        category: String = String(""),
        description: String = String(""),
        source_listing_url: String = String(""),
    ):
        self.url = url
        self.name = name
        self.price = price
        self.currency = currency
        self.image_url = image_url
        self.category = category
        self.description = description
        self.source_listing_url = source_listing_url
