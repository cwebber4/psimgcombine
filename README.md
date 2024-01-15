# psimgcombine

### Usage
<pre>
  psimgcombine.pl rowLength outputFileName inputImage [inputImage...]

  rowLength       The number of images to place on one row.
  outputFileName  The name of the image file to be created.
  inputImage      An image to include in the output image.
</pre>

This Perl script combines multiple images into one image. It does this by 
taking each specified input image and copying it onto the new image, moving 
from left to right and top to bottom according to the specified row length.

This script does not try to pack images together to maximize space, but only
processes each image in order. It is left to the user to determine the preferred 
order.

Currently, only PNG image types are produced.
