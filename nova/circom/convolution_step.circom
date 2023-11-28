pragma circom 2.0.0;

include "utils/row_hasher.circom";
include "utils/pixels.circom";
include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";


template ConvolveBlur(decompressedWidth) {
    var kernel_size = 3;
    
    signal input decompressed_row_orig[kernel_size][decompressedWidth + kernel_size -1][3];
    signal input decompressed_row_conv[decompressedWidth][3];

    var kernel[kernel_size][kernel_size];
        kernel [0][0] = 1;
        kernel [0][1] = 1;
        kernel [0][2] = 1;
        kernel [1][0] = 1;
        kernel [1][1] = 1;
        kernel [1][2] = 1;
        kernel [2][0] = 1;
        kernel [2][1] = 1;
        kernel [2][2] = 1;
    // var target_pixel_location = kernel_size \ 2 + 1;
    // var conv_value;
    var weight = 9;

    component lt[decompressedWidth][3][2];

    for (var color = 0; color < 3; color++) {
        for (var i = 0; i < decompressedWidth; i++) {
            var conv_value = 0;
            for (var m = 0; m < kernel_size; m++) {
                for (var n = 0; n < kernel_size; n++) {
                    conv_value += decompressed_row_orig[m][i + n][color] * kernel[m][n];
                    // log(decompressed_row_orig[m][i + n][color], kernel[m][n]);
                }
            }
            // log(decompressed_row_conv[i][color], conv_value);
            lt[i][color][0] = LessEqThan(16);
            lt[i][color][0].in[0] <== conv_value - decompressed_row_conv[i][color] * weight;
            lt[i][color][0].in[1] <== 9 * weight;
            lt[i][color][1] = LessEqThan(16);
            lt[i][color][1].in[0] <== decompressed_row_conv[i][color] * weight - conv_value;
            lt[i][color][1].in[1] <== 9 * weight;

            lt[i][color][0].out === 1;
            lt[i][color][1].out === 1;
        }
    }
}

template ConvolveSharpen(decompressedWidth) {
    var kernel_size = 3;
    
    signal input decompressed_row_orig[kernel_size][decompressedWidth + kernel_size -1][3];
    signal input decompressed_row_conv[decompressedWidth][3];

    var kernel[kernel_size][kernel_size];
        kernel [0][0] = 0;
        kernel [0][1] = -1;
        kernel [0][2] = 0;
        kernel [1][0] = -1;
        kernel [1][1] = 5;
        kernel [1][2] = -1;
        kernel [2][0] = 0;
        kernel [2][1] = -1;
        kernel [2][2] = 0;
    // var target_pixel_location = kernel_size \ 2 + 1;
    // var conv_value;
    var weight = 1;

    component lt[decompressedWidth][3][2];

    for (var color = 0; color < 3; color++) {
        for (var i = 0; i < decompressedWidth; i++) {
            var conv_value = 0;
            for (var m = 0; m < kernel_size; m++) {
                for (var n = 0; n < kernel_size; n++) {
                    conv_value += decompressed_row_orig[m][i + n][color] * kernel[m][n];
                }
            }
            // log(decompressed_row_conv[i][color], conv_value);
            lt[i][color][0] = LessEqThan(16);
            lt[i][color][0].in[0] <== conv_value - decompressed_row_conv[i][color];
            lt[i][color][0].in[1] <== 9;
            lt[i][color][1] = LessEqThan(16);
            lt[i][color][1].in[0] <== decompressed_row_conv[i][color] - conv_value;
            lt[i][color][1].in[1] <== 9;

            lt[i][color][0].out === 1;
            lt[i][color][1].out === 1;
        }
    }
}

template UnwrapAndExtend(width, kernel_size) {
    
    signal input row_orig[kernel_size][width];
    signal input row_conv[width];
    
    // ASSERT the Kernel matrice to be an sqaure of odd size
    // kernel_wdith === kernel_height;
    1 === kernel_size % 2;
    
    var decompressedWidth = width * 10;
    var extendedWidth = decompressedWidth + kernel_size - 1;

    signal output out_orig[kernel_size][extendedWidth][3];
    signal output out_conv [decompressedWidth][3];

    component decompressor_orig[kernel_size][width];
    for (var k = 0; k < kernel_size; k++) {
        for (var i = 0; i < kernel_size \ 2; i++) {
            out_orig[k][i][0] <== 0;  // R
            out_orig[k][i][1] <== 0;  // G
            out_orig[k][i][2] <== 0;  // B

            out_orig[k][extendedWidth - i - 1][0] <== 0;  // R
            out_orig[k][extendedWidth - i - 1][1] <== 0;  // G
            out_orig[k][extendedWidth - i - 1][2] <== 0;  // B
        }
        for (var i = 0; i < width; i++) {
            decompressor_orig[k][i] = Decompressor();
            decompressor_orig[k][i].in <== row_orig[k][i];
            for (var j = 0; j < 10; j++) {
                out_orig[k][(kernel_size\2)+i*10+j] <== decompressor_orig[k][i].out[j];
            }
        }
    }

    component decompressor_conv[width];
    for (var i = 0; i < width; i++) {
        decompressor_conv[i] = Decompressor();
        decompressor_conv[i].in <== row_conv[i];
        for (var j = 0; j < 10; j++) {
            out_conv[i*10+j] <== decompressor_conv[i].out[j];
        }
    }
}

template BlurCheck(width, kernel_size) {

    signal input row_orig[kernel_size][width];
    signal input row_conv[width];

    component unwrapper = UnwrapAndExtend(width, kernel_size);
    unwrapper.row_orig <== row_orig;
    unwrapper.row_conv <== row_conv;

    // ----------------------------
    // Execute Convolution
    // ----------------------------
    var decompressedWidth = width * 10;
    component blur_checker = ConvolveBlur(decompressedWidth);
    blur_checker.decompressed_row_orig <== unwrapper.out_orig;
    blur_checker.decompressed_row_conv <== unwrapper.out_conv;
}

template SharpenCheck(width, kernel_size) {

    signal input row_orig[kernel_size][width];
    signal input row_conv[width];

    component unwrapper = UnwrapAndExtend(width, kernel_size);
    unwrapper.row_orig <== row_orig;
    unwrapper.row_conv <== row_conv;

    // ----------------------------
    // Execute Convolution
    // ----------------------------
    var decompressedWidth = width * 10;
    component sharpen_checker = ConvolveSharpen(decompressedWidth);
    sharpen_checker.decompressed_row_orig <== unwrapper.out_orig;
    sharpen_checker.decompressed_row_conv <== unwrapper.out_conv;
}

template IntegrityCheck(width, kernel_size) {
    // public inputs and outputs
    signal input step_in[kernel_size+1];
    // signal input prev_orig_hash_0;
    // signal input prev_orig_hash_1;
    // signal input prev_orig_hash_2;
    // signal input prev_orig_hash_3;
    // signal input prev_orig_hash;
    // signal input prev_conv_hash;
    // signal input compressed_kernel;
    
    signal output step_out[kernel_size+1];
    // signal output next_orig_hash_1;
    // signal output next_orig_hash_2;
    // signal output next_orig_hash_3;
    // signal output next_orig_hash_4;
    // signal output next_orig_hash;
    // signal output next_conv_hash;
    // signal output compressed_kernel;
    
    // private inputs
    signal input row_orig [kernel_size][width];
    signal input row_conv [width];

    var row_hashes[kernel_size];

    component orig_row_hasher[kernel_size];
    component orig_hasher;

    for (var i = 0; i < kernel_size; i++) {
        orig_row_hasher[i] = RowHasher(width);
        orig_row_hasher[i].img <== row_orig[i];
        row_hashes[i] = orig_row_hasher[i].hash;
    }
    
    orig_hasher = Hasher(2);
    orig_hasher.values[0] <== step_in[kernel_size-1];
    orig_hasher.values[1] <== row_hashes[(kernel_size \ 2) + 1]; // hash with hash of middle row  
    step_out[kernel_size-1] <== orig_hasher.hash;

    component conv_row_hasher;
    component conv_hasher;

    conv_row_hasher = RowHasher(width);
    conv_row_hasher.img <== row_conv;

    conv_hasher = Hasher(2);
    conv_hasher.values[0] <== step_in[kernel_size];
    conv_hasher.values[1] <== conv_row_hasher.hash; 
    step_out[kernel_size] <== conv_hasher.hash;

    component zero_checker[kernel_size - 1];
    for (var i = 0; i < kernel_size-1; i++) {
        zero_checker[i] = IsZero();
        zero_checker[i].in <== step_in[i];
        row_hashes[i] * (1 - zero_checker[i].out) === step_in[i];
        step_out[i] <== row_hashes[i+1]; 
    }

    // log(row_hashes[0], row_hashes[1], row_hashes[2]);

    // component decompressor_kernel = DecompressorKernel(kernel_size);
    // decompressor_kernel.in <== step_in[kernel_size+1];

    // component conv_checker = SharpenCheck(width, kernel_size);
    // conv_checker.row_orig <== row_orig;
    // conv_checker.row_conv <== row_conv;
    // conv_checker.kernel <== decompressor_kernel.out;

}

// component main { public [step_in] } = IntegrityCheck(128, 3);