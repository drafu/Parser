use strict;
use warnings;
use JSON::MaybeXS qw/encode_json/;
use File::Basename;

local $/ = undef; # Глобальная перловая магическая переменная для считываения бинарников.
my $errors = 0;
my @error_msg;
{
    my ($name, $path, $suffix) = fileparse($ARGV[0]);
    open FILE, $ARGV[0] or die "Couldn't open file: $!";
    my $string = <FILE>; # Читаем файл целиком.
    close FILE;

    my @blocks = $string =~ /RD006.*\n(\X+?(?=\|\|001F))/g; # Забираем только блоки данных между RD006 и ||001F

    my @all_blocks;
    foreach (@blocks) { # Итерируем по каждому блоку отдельно
        push @all_blocks, {raw => length $_, result => readblock($_)};
    }

    # Выводим все полученные ошибки
    open my $logfh, ">", "$name.log";
    print $logfh "Total errors: " . (scalar @error_msg) . "\n------------------\n";
    foreach (@error_msg) {
       print $logfh "$_\n";
    }
    close $logfh;

    # print Dumper \@all_blocks; # Выводим текстом готовые данные
    print "Completed with $errors errors\n"; # И количество ошибок

    open my $fh, ">", "$name.json";
    print $fh encode_json(\@all_blocks);
    close $fh;
}

sub readblock {
    my $block = shift;
    my @block_array = split(//, $block); # Разбиваем строку на массив символов
    my @lines;
    readlines(\@block_array, 0, \@lines); # Кормим функцию первой строкой и дальше она сама будет идти по всем строчкам дальше
    # print Dumper @lines;
    return \@lines;
}

sub readlines {
    my ($block, $start, $lines) = @_;
    my $line_name = @{$block}[$start] . @{$block}[$start + 1]; # Первые 2 символа строки всегда имя блока
    my $line_length_hex = @{$block}[$start + 2] . @{$block}[$start + 3] . @{$block}[$start + 4]; # 3-5 символы всегда длина блока в 16-ричной системе
    my $line_length = hex($line_length_hex); # Конвертируем в десятичное число

    my $total_line_length = $start + 5 + $line_length;

    my @hex;
    my @line;

    my $line_error = 0;

    for(my $i = $start + 5; $i <= $total_line_length; $i++) { # Итерируем по строке от стартового байта данных $start + 5 и заканчивая по длине $total_line_length
        my $symbol = @{$block}[$i]; # Текущий символ
        my $byte =  unpack 'H2', $symbol; # Текущий символ в HEX

        if($i == $total_line_length) { # 0A -- это всегда конец строки. Если это так, то переходим к следующей.
            if($byte eq '0a') {
                readlines($block, $total_line_length + 1, $lines); # Успешно считанная линия.
            } else { # Что-то не так. Символы кончились, но последний символ не прерывающий. Значит, неверная длина строки. Продолжать весь блок невозможно.
                $errors++;
                push @error_msg, "Unexpected end of line $line_name$line_length_hex, wrong line length";
                $line_error = 1;
                last;
            }
        } else {
            push @hex, $byte;
            push @line, $symbol;
        }

        if ( (unpack 'H6', @{$block}[$i] . @{$block}[$i + 1] . @{$block}[$i + 2]) eq 'efbfbd' ) { # Ищем последовательность EFBFDF, являющуся 1 символом, но 3 байтами.
            $total_line_length += 2; # И если находим, прибавляем к длине строки 2.
        }
    }

    my $result = {
        name => $line_name,
        length => $line_length,
        error => $line_error,
        # hex => \@hex,
        symbols => join('', @line)
    };
    unshift @{$lines}, $result;
    return $lines;
}
