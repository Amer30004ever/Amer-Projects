<html>
    <head>
        <title>My Shop</title>
    </head>
    <body>
        <h1>Welcome to my shop</h1>
        <ul>
            <?php
            try {
                $json = file_get_contents('http://product-service/');
                $obj = json_decode($json);
                $products = $obj->products;

                foreach ($products as $product) {
                    echo "<li>$product</li>";
                }
            } catch (Exception $e) {
                echo "<li>Could not load products. Please try again later.</li>";
            }
            ?>
        </ul>
    </body>
</html>
